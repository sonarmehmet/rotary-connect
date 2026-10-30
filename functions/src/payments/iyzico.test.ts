import { describe, expect, it } from "vitest";
import { createHmac } from "node:crypto";
import { handleIyzicoWebhook } from "../handlers/iyzicoWebhook";
import { EventRegistrationService } from "../events/service";
import { MemoryEffects } from "../testing/memoryEffects";
import { MemoryPayments } from "../testing/memoryPayments";
import { MemoryStore } from "../testing/memoryStore";
import { startPayment } from "./startPayment";
import { EffectsDeps } from "./effects";
import {
  IyzicoHttp, IyzicoProvider, iyzicoHppSignature, minorToPrice, parseIyzicoWebhook, priceToMinor, verifyIyzicoHppSignature,
} from "./iyzico";

const NOW = 1_800_000_000_000;
const SECRET = "test-secret";
const payload = { iyziEventType: "CHECKOUT_FORM_AUTH", iyziPaymentId: "9001", token: "tok-1", paymentConversationId: "id1", status: "SUCCESS" };

describe("iyzico yardımcıları", () => {
  it("tutar dönüşümü kayıpsız ve float'sız", () => {
    expect(minorToPrice(12345)).toBe("123.45");
    expect(minorToPrice(5)).toBe("0.05");
    expect(minorToPrice(100)).toBe("1.00");
    expect(priceToMinor("123.45")).toBe(12345);
    expect(priceToMinor("123.4")).toBe(12340);
    expect(priceToMinor("100")).toBe(10000);
    expect(priceToMinor(10.5)).toBe(1050);
    expect(priceToMinor("abc")).toBe(null);
    expect(priceToMinor("1.234")).toBe(null);
  });

  it("imza: dokümandaki dizgiyle HMAC-SHA256 hex; yanlış/eksik imza reddedilir", () => {
    const expected = createHmac("sha256", SECRET)
      .update(SECRET + "CHECKOUT_FORM_AUTH" + "9001" + "tok-1" + "id1" + "SUCCESS", "utf8").digest("hex");
    expect(iyzicoHppSignature(SECRET, payload)).toBe(expected);
    expect(verifyIyzicoHppSignature(SECRET, payload, expected)).toBe(true);
    expect(verifyIyzicoHppSignature(SECRET, payload, expected.toUpperCase())).toBe(true);
    expect(verifyIyzicoHppSignature(SECRET, payload, "00" + expected.slice(2))).toBe(false);
    expect(verifyIyzicoHppSignature(SECRET, payload, undefined)).toBe(false);
    expect(verifyIyzicoHppSignature(SECRET, { ...payload, status: "FAILURE" }, expected)).toBe(false);
  });

  it("webhook gövdesi eksikse null", () => {
    expect(parseIyzicoWebhook(null)).toBe(null);
    expect(parseIyzicoWebhook({ status: "SUCCESS" })).toBe(null);
    expect(parseIyzicoWebhook(payload)?.token).toBe("tok-1");
  });
});

function fakeHttp(detail: Record<string, unknown>): IyzicoHttp & { calls: string[] } {
  const calls: string[] = [];
  return {
    calls,
    async post(path) {
      calls.push(path);
      return path.includes("initialize")
        ? { status: "success", token: "tok-1", paymentPageUrl: "https://pay.example/tok-1" }
        : detail;
    },
  };
}
const buyerFor = async () => ({ id: "b", name: "A", surname: "B", email: "a@b.co", ip: "1.1.1.1" });

describe("IyzicoProvider", () => {
  it("oturum açar; getResult tutarı iyzico'dan alır", async () => {
    const http = fakeHttp({ status: "success", paymentStatus: "SUCCESS", paidPrice: "1000.00", currency: "TRY" });
    const p = new IyzicoProvider({ http, callbackUrl: "https://x/cb", buyerFor });
    const s = await p.createSession({ paymentId: "id1", amount: { amountMinor: 100_000, currency: "TRY" }, description: "Aidat" });
    expect(s).toEqual({ providerRef: "tok-1", checkoutUrl: "https://pay.example/tok-1", simulated: false });
    expect(await p.getResult("tok-1")).toEqual({ status: "succeeded", amountMinor: 100_000, currency: "TRY" });
  });

  it("sorgu başarısızsa karar vermez (pending); başarısız ödeme kodu taşır", async () => {
    const bad = new IyzicoProvider({ http: fakeHttp({ status: "failure" }), callbackUrl: "x", buyerFor });
    expect((await bad.getResult("t")).status).toBe("pending");
    const fail = new IyzicoProvider({ http: fakeHttp({ status: "success", paymentStatus: "FAILURE", errorCode: "10051", paidPrice: "10.00", currency: "TRY" }), callbackUrl: "x", buyerFor });
    expect(await fail.getResult("t")).toEqual({ status: "failed", amountMinor: 1000, currency: "TRY", failureCode: "10051" });
  });
});

async function webhookSetup(detail: Record<string, unknown>) {
  const payments = new MemoryPayments();
  const fx = new MemoryEffects();
  const provider = new IyzicoProvider({ http: fakeHttp(detail), callbackUrl: "x", buyerFor });
  fx.dues.set("due1", { id: "due1", userId: "u1", currency: "TRY", amountMinor: 100_000, paidMinor: 0, dueDateMs: NOW + 86_400_000, cancelled: false, refunded: false, allowPartial: false, status: "unpaid" });
  const started = await startPayment(payments, provider, {
    kind: "membership_due", refId: "due1", userId: "u1", amount: { amountMinor: 100_000, currency: "TRY" },
    clientKey: "client-key-1", description: "Aidat", nowMs: NOW, mode: "live", newId: () => "id1",
  });
  const effects: EffectsDeps = {
    runner: fx, events: new EventRegistrationService(new MemoryStore([])),
    notifications: { createIfAbsent: async () => undefined }, refunds: { request: async () => undefined }, nowMs: () => NOW,
  };
  const deps = { secretKey: SECRET, provider, payments, effects, nowMs: () => NOW };
  const sig = iyzicoHppSignature(SECRET, payload);
  return { deps, fx, payments, started, sig };
}

describe("iyzico webhook işleyicisi", () => {
  it("geçerli imza + doğrulanmış tutar: ödeme kapanır, borç yansır; tekrar 200 ve etkisiz", async () => {
    const { deps, fx, sig } = await webhookSetup({ status: "success", paymentStatus: "SUCCESS", paidPrice: "1000.00", currency: "TRY" });
    expect((await handleIyzicoWebhook(deps, sig, payload)).httpStatus).toBe(200);
    expect(fx.dues.get("due1")?.status).toBe("paid");
    expect((await handleIyzicoWebhook(deps, sig, payload)).httpStatus).toBe(200);
    expect(fx.duePayments.length).toBe(1);
  });

  it("imza hatalıysa 401 ve hiçbir şey değişmez; bozuk gövde 400", async () => {
    const { deps, fx, payments } = await webhookSetup({ status: "success", paymentStatus: "SUCCESS", paidPrice: "1000.00", currency: "TRY" });
    expect((await handleIyzicoWebhook(deps, "yanlis", payload)).httpStatus).toBe(401);
    expect((await handleIyzicoWebhook(deps, "x", { foo: 1 })).httpStatus).toBe(400);
    expect(fx.dues.get("due1")?.paidMinor).toBe(0);
    expect(payments.all()[0]?.status).toBe("pending");
  });

  it("webhook SUCCESS dese de iyzico sorgusu farklı tutar dönerse tahsilat sayılmaz", async () => {
    const { deps, fx, payments, sig } = await webhookSetup({ status: "success", paymentStatus: "SUCCESS", paidPrice: "1.00", currency: "TRY" });
    expect((await handleIyzicoWebhook(deps, sig, payload)).httpStatus).toBe(200);
    expect(payments.all()[0]?.flag).toBe("amount_mismatch");
    expect(fx.dues.get("due1")?.paidMinor).toBe(0);
  });

  it("iyzico henüz sonuçlanmadı diyorsa 200 döner, ödeme pending kalır", async () => {
    const { deps, payments, sig } = await webhookSetup({ status: "success", paymentStatus: "INIT_THREEDS" });
    expect((await handleIyzicoWebhook(deps, sig, payload)).httpStatus).toBe(200);
    expect(payments.all()[0]?.status).toBe("pending");
  });
});

describe("iyzico iadesi", () => {
  it("ödeme ayrıntısından paymentId alır, tutar bazlı iade eder, anahtarı conversationId yapar", async () => {
    const sent: { path: string; body: Record<string, unknown> }[] = [];
    const http: IyzicoHttp = {
      async post(path, body) {
        sent.push({ path, body });
        return path.includes("detail") ? { status: "success", paymentId: "9001" } : { status: "success" };
      },
    };
    const p = new IyzicoProvider({ http, callbackUrl: "x", buyerFor });
    await p.refund("tok-1", 2_500, "refund_pay1_0_2500");
    expect(sent[1]?.path).toBe("/v2/payment/refund");
    expect(sent[1]?.body["paymentId"]).toBe("9001");
    expect(sent[1]?.body["price"]).toBe("25.00");
    expect(sent[1]?.body["conversationId"]).toBe("refund_pay1_0_2500");
  });

  it("iyzico reddederse veya ayrıntı alınamazsa hata fırlatır", async () => {
    const noDetail = new IyzicoProvider({ http: { post: async () => ({ status: "failure" }) }, callbackUrl: "x", buyerFor });
    await expect(noDetail.refund("t", 100, "k")).rejects.toThrow();
    const denied = new IyzicoProvider({
      http: { post: async (path) => (path.includes("detail") ? { status: "success", paymentId: "1" } : { status: "failure", errorCode: "5" }) },
      callbackUrl: "x", buyerFor,
    });
    await expect(denied.refund("t", 100, "k")).rejects.toThrow();
  });
});
