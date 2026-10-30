import { describe, expect, it } from "vitest";
import { constantTimeEqual } from "../lib/safeEqual";
import { DomainError } from "../lib/errors";
import { MemoryPayments } from "../testing/memoryPayments";
import { SimulatedProvider } from "./provider";
import { startPayment, StartPaymentInput } from "./startPayment";
import { ProviderEvent, processWebhook } from "./webhook";

const NOW = 1_800_000_000_000;

function input(over: Partial<StartPaymentInput> = {}): StartPaymentInput {
  let n = 0;
  return {
    kind: "donation",
    refId: "camp1",
    userId: "u1",
    amount: { amountMinor: 25_000, currency: "TRY" },
    clientKey: "client-key-1",
    description: "Test bağışı",
    nowMs: NOW,
    mode: "simulation",
    newId: () => `id${++n}`,
    ...over,
  };
}

async function reasonOf(p: Promise<unknown>): Promise<string> {
  try {
    await p;
    return "no-error";
  } catch (e) {
    return e instanceof DomainError ? (e.reason ?? e.code) : "other";
  }
}

const ok = (providerRef: string, over: Partial<ProviderEvent> = {}): ProviderEvent => ({
  providerRef,
  status: "succeeded",
  amountMinor: 25_000,
  currency: "TRY",
  ...over,
});

describe("sabit zamanlı karşılaştırma", () => {
  it("eşit ve farklı dizeler", () => {
    expect(constantTimeEqual("abc", "abc")).toBe(true);
    expect(constantTimeEqual("abc", "abd")).toBe(false);
    expect(constantTimeEqual("abc", "abcd")).toBe(false);
    expect(constantTimeEqual("", "")).toBe(true);
  });
});

describe("startPayment", () => {
  it("ödeme kaydı açar, pending yapar ve simülasyonu işaretler", async () => {
    const db = new MemoryPayments();
    const r = await startPayment(db, new SimulatedProvider(), input());
    expect(r.payment.status).toBe("pending");
    expect(r.payment.simulated).toBe(true);
    expect(r.payment.providerRef).toMatch(/^SIM-/);
    expect(db.all().length).toBe(1);
  });

  it("aynı anahtarla 10 paralel çağrı TEK ödeme oluşturur", async () => {
    const db = new MemoryPayments();
    const provider = new SimulatedProvider();
    const rs = await Promise.all(Array.from({ length: 10 }, () => startPayment(db, provider, input())));
    expect(db.all().length).toBe(1);
    expect(rs.filter((r) => !r.reused).length).toBe(1);
  });

  it("farklı anahtar farklı ödeme; aynı anahtar farklı tutar reddedilir", async () => {
    const db = new MemoryPayments();
    const provider = new SimulatedProvider();
    await startPayment(db, provider, input());
    await startPayment(db, provider, input({ clientKey: "client-key-2" }));
    expect(db.all().length).toBe(2);
    expect(
      await reasonOf(
        startPayment(db, provider, input({ amount: { amountMinor: 99_999, currency: "TRY" } })),
      ),
    ).toBe("key_amount_mismatch");
  });

  it("geçersiz tutar ve kısa anahtar reddedilir", async () => {
    const db = new MemoryPayments();
    const provider = new SimulatedProvider();
    await expect(
      startPayment(db, provider, input({ amount: { amountMinor: 0, currency: "TRY" } })),
    ).rejects.toThrow();
    expect(await reasonOf(startPayment(db, provider, input({ clientKey: "x" })))).toBe("bad_client_key");
  });

  it("canlı modda simülasyon sağlayıcısı engellenir ve ödeme başarısız işaretlenir", async () => {
    const db = new MemoryPayments();
    expect(await reasonOf(startPayment(db, new SimulatedProvider(), input({ mode: "live" })))).toBe(
      "simulated_in_live",
    );
    expect(db.all()[0]?.status).toBe("failed");
  });
});

describe("processWebhook", () => {
  async function pending() {
    const db = new MemoryPayments();
    const r = await startPayment(db, new SimulatedProvider(), input());
    return { db, ref: r.payment.providerRef as string };
  }

  it("geçersiz imza hiçbir şeyi değiştirmez", async () => {
    const { db, ref } = await pending();
    expect(
      await reasonOf(processWebhook(db, { event: ok(ref), signatureValid: false, nowMs: NOW })),
    ).toBe("bad_signature");
    expect(db.all()[0]?.status).toBe("pending");
  });

  it("başarılı bildirim ödemeyi tahsil edilmiş yapar ve etki üretir", async () => {
    const { db, ref } = await pending();
    const out = await processWebhook(db, { event: ok(ref), signatureValid: true, nowMs: NOW + 5 });
    expect(out.result).toBe("applied");
    if (out.result === "applied") expect(out.effects.map((e) => e.type)).toEqual(["collected"]);
    expect(db.all()[0]?.status).toBe("succeeded");
    expect(db.all()[0]?.succeededAtMs).toBe(NOW + 5);
  });

  it("aynı bildirim 8 kez eşzamanlı gelse de TEK kez uygulanır", async () => {
    const { db, ref } = await pending();
    const outs = await Promise.all(
      Array.from({ length: 8 }, () => processWebhook(db, { event: ok(ref), signatureValid: true, nowMs: NOW })),
    );
    expect(outs.filter((o) => o.result === "applied").length).toBe(1);
    expect(outs.filter((o) => o.result === "ignored").length).toBe(7);
    expect(db.all()[0]?.status).toBe("succeeded");
  });

  it("sıra bozukluğu: başarıdan sonra gelen 'pending' ve 'failed' yok sayılır", async () => {
    const { db, ref } = await pending();
    await processWebhook(db, { event: ok(ref), signatureValid: true, nowMs: NOW });
    for (const status of ["pending", "failed"] as const) {
      const out = await processWebhook(db, {
        event: ok(ref, { status, amountMinor: null, currency: null }),
        signatureValid: true,
        nowMs: NOW,
      });
      expect(out.result).toBe("ignored");
    }
    expect(db.all()[0]?.status).toBe("succeeded");
  });

  it("başarısız bildirim hata kodunu yazar; sonradan 'succeeded' gelse de değişmez", async () => {
    const { db, ref } = await pending();
    const out = await processWebhook(db, {
      event: ok(ref, { status: "failed", amountMinor: null, currency: null, failureCode: "insufficient_funds" }),
      signatureValid: true,
      nowMs: NOW,
    });
    expect(out.result).toBe("applied");
    expect(db.all()[0]?.failureCode).toBe("insufficient_funds");
    const late = await processWebhook(db, { event: ok(ref), signatureValid: true, nowMs: NOW });
    expect(late.result).toBe("ignored");
    expect(db.all()[0]?.status).toBe("failed");
  });

  it("tutar uyuşmazlığı: tahsilat sayılmaz, işaretlenir, ödeme pending kalır", async () => {
    const { db, ref } = await pending();
    const out = await processWebhook(db, {
      event: ok(ref, { amountMinor: 100 }),
      signatureValid: true,
      nowMs: NOW,
    });
    expect(out.result).toBe("flagged");
    expect(db.all()[0]?.status).toBe("pending");
    expect(db.all()[0]?.flag).toBe("amount_mismatch");
  });

  it("para birimi uyuşmazlığı da işaretlenir", async () => {
    const { db, ref } = await pending();
    const out = await processWebhook(db, {
      event: ok(ref, { currency: "EUR" }),
      signatureValid: true,
      nowMs: NOW,
    });
    expect(out.result).toBe("flagged");
  });

  it("bilinmeyen sağlayıcı referansı yok sayılır", async () => {
    const { db } = await pending();
    const out = await processWebhook(db, { event: ok("NOPE"), signatureValid: true, nowMs: NOW });
    expect(out).toEqual({ result: "ignored", reason: "unknown_payment" });
  });
});
