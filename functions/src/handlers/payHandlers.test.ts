import { describe, expect, it } from "vitest";
import { RegistrationDoc } from "../events/capacity";
import { SimulatedProvider } from "../payments/provider";
import { MemoryPayments } from "../testing/memoryPayments";
import { toCallableError } from "./callableError";
import { CallableAuth } from "./handlers";
import { DueReader, RegistrationReader, startDuePaymentHandler, startEventFeePaymentHandler } from "./payHandlers";

const NOW = 1_800_000_000_000;
const DAY = 86_400_000;
const auth = (uid: string): CallableAuth => ({ uid, token: {} });

async function failure(p: Promise<unknown>): Promise<string> {
  try {
    await p;
    return "no-error";
  } catch (e) {
    const c = toCallableError(e);
    return `${c.code}:${c.reason ?? ""}`;
  }
}

function base() {
  let n = 0;
  return { payments: new MemoryPayments(), provider: new SimulatedProvider(), nowMs: () => NOW, mode: "simulation" as const, newId: () => `id${++n}` };
}

const dues: DueReader = {
  get: async (id) =>
    id === "due1"
      ? { userId: "u1", currency: "TRY", amountMinor: 120_000, paidMinor: 20_000, dueDateMs: NOW + DAY, cancelled: false, refunded: false, allowPartial: true }
      : null,
};

const reg = (over: Partial<RegistrationDoc> = {}): RegistrationDoc => ({
  id: "r1", eventId: "ev1", userId: "u1", participant: { name: "Ali", email: "a@b.co" }, status: "reserved",
  paymentId: null, reservedUntilMs: NOW + DAY, waitlistPosition: null, createdAtMs: NOW, confirmedAtMs: null, ...over,
});

const regs = (r: RegistrationDoc | null, fee = 50_000): RegistrationReader => ({
  get: async () => r,
  eventFee: async () => ({ feeMinor: fee, currency: "TRY" }),
});

describe("aidat ödemesi başlatma", () => {
  it("tutar borçtan çözülür (kalan tutar), istemci tutarı gerekmez", async () => {
    const deps = { ...base(), dues, partialEnabled: async () => true };
    const out = await startDuePaymentHandler(deps, auth("u1"), { dueId: "due1", clientKey: "client-key-1" });
    expect(deps.payments.all()[0]?.amountMinor).toBe(100_000);
    expect(out.simulated).toBe(true);
  });

  it("kısmi tutar yalnızca izin varsa; aksi halde reddedilir", async () => {
    const d1 = { ...base(), dues, partialEnabled: async () => true };
    await startDuePaymentHandler(d1, auth("u1"), { dueId: "due1", clientKey: "client-key-1", amountMinor: 30_000 });
    expect(d1.payments.all()[0]?.amountMinor).toBe(30_000);
    const d2 = { ...base(), dues, partialEnabled: async () => false };
    expect(await failure(startDuePaymentHandler(d2, auth("u1"), { dueId: "due1", clientKey: "client-key-1", amountMinor: 30_000 }))).toBe(
      "failed-precondition:due_partial_not_allowed",
    );
  });

  it("başkasının borcu ve var olmayan borç aynı hatayı verir; girişsiz çağrı reddedilir", async () => {
    const deps = { ...base(), dues, partialEnabled: async () => true };
    expect(await failure(startDuePaymentHandler(deps, auth("u2"), { dueId: "due1", clientKey: "client-key-1" }))).toBe("not-found:due_not_found");
    expect(await failure(startDuePaymentHandler(deps, auth("u1"), { dueId: "yok", clientKey: "client-key-1" }))).toBe("not-found:due_not_found");
    expect(await failure(startDuePaymentHandler(deps, null, { dueId: "due1", clientKey: "client-key-1" }))).toBe("unauthenticated:login_required");
  });

  it("aynı clientKey ile tekrar çağrı aynı ödemeyi döner", async () => {
    const deps = { ...base(), dues, partialEnabled: async () => true };
    const a = await startDuePaymentHandler(deps, auth("u1"), { dueId: "due1", clientKey: "client-key-1" });
    const b = await startDuePaymentHandler(deps, auth("u1"), { dueId: "due1", clientKey: "client-key-1" });
    expect(b.paymentId).toBe(a.paymentId);
    expect(b.reused).toBe(true);
    expect(deps.payments.all().length).toBe(1);
  });
});

describe("etkinlik ücreti ödemesi başlatma", () => {
  it("tutar etkinlik kaydındaki ücrettir", async () => {
    const deps = { ...base(), registrations: regs(reg(), 75_000) };
    await startEventFeePaymentHandler(deps, auth("u1"), { registrationId: "r1", clientKey: "client-key-1", amountMinor: 1 });
    expect(deps.payments.all()[0]?.amountMinor).toBe(75_000);
    expect(deps.payments.all()[0]?.refId).toBe("r1");
  });

  it("başkasının kaydı, ödenemez durum, süresi dolmuş rezervasyon ve ücretsiz etkinlik reddedilir", async () => {
    const mk = (r: RegistrationDoc | null, fee?: number) => ({ ...base(), registrations: regs(r, fee) });
    const call = (d: ReturnType<typeof mk>, uid = "u1") => startEventFeePaymentHandler(d, auth(uid), { registrationId: "r1", clientKey: "client-key-1" });
    expect(await failure(call(mk(reg()), "u2"))).toBe("not-found:registration_not_found");
    expect(await failure(call(mk(reg({ status: "confirmed" }))))).toBe("failed-precondition:registration_not_payable");
    expect(await failure(call(mk(reg({ status: "waitlisted" }))))).toBe("failed-precondition:registration_not_payable");
    expect(await failure(call(mk(reg({ reservedUntilMs: NOW - 1 }))))).toBe("failed-precondition:reservation_expired");
    expect(await failure(call(mk(reg(), 0)))).toBe("failed-precondition:free_event");
  });
});
