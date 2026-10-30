import { describe, expect, it } from "vitest";
import { AuditEntry } from "../audit/audit";
import { EventDoc } from "../events/capacity";
import { EventRegistrationService } from "../events/service";
import { CallableAuth, recordManualPaymentHandler } from "../handlers/handlers";
import { NotificationItem } from "../notifications/notifications";
import { MemoryEffects } from "../testing/memoryEffects";
import { MemoryPayments } from "../testing/memoryPayments";
import { MemoryStore } from "../testing/memoryStore";
import { EffectsDeps, applyCollected, applyEffects, applyFailed } from "./effects";
import { PaymentDoc } from "./repo";

const NOW = 1_800_000_000_000;
const DAY = 86_400_000;

function pay(over: Partial<PaymentDoc>): PaymentDoc {
  return {
    id: "p1", kind: "membership_due", refId: "due1", userId: "u1", amountMinor: 120_000, currency: "TRY",
    status: "succeeded", provider: "iyzico", providerRef: "R1", simulated: false, idempotencyKey: "k",
    manual: false, recordedBy: null, note: null, refundedMinor: 0, createdAtMs: NOW, updatedAtMs: NOW,
    succeededAtMs: NOW, failureCode: null, flag: null, ...over,
  };
}

function eventDoc(over: Partial<EventDoc> = {}): EventDoc {
  return {
    id: "ev1", capacity: 2, reservedCount: 0, confirmedCount: 0, waitlistEnabled: true, status: "published",
    registrationDeadlineMs: NOW + DAY, feeMinor: 50_000, currency: "TRY", ...over,
  };
}

function setup(events: EventDoc[] = [eventDoc()]) {
  const fx = new MemoryEffects();
  const notes = new Map<string, NotificationItem>();
  const refundCalls: { paymentId: string; reason: string }[] = [];
  const store = new MemoryStore(events);
  const svc = new EventRegistrationService(store);
  const deps: EffectsDeps = {
    runner: fx,
    events: svc,
    notifications: { createIfAbsent: async (items) => void items.forEach((i) => notes.has(i.id) || notes.set(i.id, i)) },
    refunds: { request: async (p, reason) => void (refundCalls.some((r) => r.paymentId === p.id) || refundCalls.push({ paymentId: p.id, reason })) },
    nowMs: () => NOW,
  };
  fx.dues.set("due1", {
    id: "due1", userId: "u1", currency: "TRY", amountMinor: 120_000, paidMinor: 0, dueDateMs: NOW + 30 * DAY,
    cancelled: false, refunded: false, allowPartial: true, status: "unpaid",
  });
  fx.campaigns.set("c1", { verifiedTotalMinor: 10_000, donorCount: 1 });
  fx.donations.set("d1", { id: "d1", paymentId: "p1", status: "pending" });
  return { fx, notes, refundCalls, store, svc, deps };
}

describe("aidat etkisi", () => {
  it("ödeme borcu kapatır, kayıt ve bildirim oluşturur", async () => {
    const { fx, notes, deps } = setup();
    expect(await applyCollected(deps, pay({}))).toEqual({ result: "applied" });
    expect(fx.dues.get("due1")?.paidMinor).toBe(120_000);
    expect(fx.dues.get("due1")?.status).toBe("paid");
    expect(fx.duePayments).toEqual([
      { dueId: "due1", paymentId: "p1", userId: "u1", amountMinor: 120_000, currency: "TRY", source: "online", createdAtMs: NOW },
    ]);
    expect([...notes.values()][0]?.doc.type).toBe("due_paid");
  });

  it("aynı ödeme tekrar uygulanırsa borç iki kez düşmez, bildirim çoğalmaz", async () => {
    const { fx, notes, deps } = setup();
    await applyCollected(deps, pay({ amountMinor: 50_000 }));
    expect(await applyCollected(deps, pay({ amountMinor: 50_000 }))).toEqual({ result: "already_applied" });
    expect(fx.dues.get("due1")?.paidMinor).toBe(50_000);
    expect(fx.duePayments.length).toBe(1);
    expect(notes.size).toBe(1);
  });

  it("6 eşzamanlı uygulama tek kez işler", async () => {
    const { fx, deps } = setup();
    const outs = await Promise.all(Array.from({ length: 6 }, () => applyCollected(deps, pay({ amountMinor: 40_000 }))));
    expect(outs.filter((o) => o.result === "applied").length).toBe(1);
    expect(fx.dues.get("due1")?.paidMinor).toBe(40_000);
  });

  it("kısmi ödeme durumu partially_paid olur; ikinci ödeme kalanı kapatır", async () => {
    const { fx, deps } = setup();
    await applyCollected(deps, pay({ id: "pa", amountMinor: 50_000 }));
    expect(fx.dues.get("due1")?.status).toBe("partially_paid");
    await applyCollected(deps, pay({ id: "pb", amountMinor: 70_000 }));
    expect(fx.dues.get("due1")?.status).toBe("paid");
  });

  it("fazla ödeme, iptal edilmiş borç, olmayan borç ve para birimi uyuşmazlığında iade talebi açılır", async () => {
    const a = setup();
    a.fx.dues.set("due1", { ...a.fx.dues.get("due1")!, paidMinor: 120_000 });
    expect(await applyCollected(a.deps, pay({}))).toEqual({ result: "refund_required", reason: "overpayment" });
    expect(a.fx.dues.get("due1")?.paidMinor).toBe(120_000);
    expect(a.notes.size).toBe(0);

    const b = setup();
    b.fx.dues.set("due1", { ...b.fx.dues.get("due1")!, cancelled: true });
    expect((await applyCollected(b.deps, pay({}))).result).toBe("refund_required");
    expect(b.refundCalls[0]?.reason).toBe("due_not_payable");

    const c = setup();
    expect(await applyCollected(c.deps, pay({ refId: "yok" }))).toEqual({ result: "refund_required", reason: "due_not_found" });

    const d = setup();
    expect(await applyCollected(d.deps, pay({ currency: "EUR" }))).toEqual({ result: "refund_required", reason: "currency_mismatch" });
  });

  it("iade talebi tekrar çağrıda çoğalmaz", async () => {
    const { fx, refundCalls, deps } = setup();
    fx.dues.set("due1", { ...fx.dues.get("due1")!, paidMinor: 120_000 });
    await applyCollected(deps, pay({}));
    await applyCollected(deps, pay({}));
    expect(refundCalls.length).toBe(1);
  });
});

describe("bağış etkisi", () => {
  const don = (over: Partial<PaymentDoc> = {}) => pay({ kind: "donation", refId: "c1", amountMinor: 25_000, ...over });

  it("bağış kaydı succeeded olur, kampanya doğrulanmış toplamı artar", async () => {
    const { fx, deps } = setup();
    await applyCollected(deps, don());
    expect(fx.donations.get("d1")?.status).toBe("succeeded");
    expect(fx.campaigns.get("c1")).toEqual({ verifiedTotalMinor: 35_000, donorCount: 2 });
  });

  it("tekrar uygulama toplamı iki kez artırmaz", async () => {
    const { fx, deps } = setup();
    await applyCollected(deps, don());
    await applyCollected(deps, don());
    expect(fx.campaigns.get("c1")?.verifiedTotalMinor).toBe(35_000);
  });

  it("SİMÜLASYON ödemesi kampanya toplamına girmez ama bağış kaydı ilerler", async () => {
    const { fx, deps } = setup();
    await applyCollected(deps, don({ simulated: true }));
    expect(fx.campaigns.get("c1")).toEqual({ verifiedTotalMinor: 10_000, donorCount: 1 });
    expect(fx.donations.get("d1")?.status).toBe("succeeded");
  });

  it("genel bağış (kampanyasız) ve bağış kaydı olmayan manuel bağış sorunsuz işlenir", async () => {
    const { fx, deps } = setup();
    expect((await applyCollected(deps, don({ refId: "general" }))).result).toBe("applied");
    expect((await applyCollected(deps, don({ id: "pm", manual: true, provider: "manual" }))).result).toBe("applied");
    expect(fx.campaigns.get("c1")?.verifiedTotalMinor).toBe(35_000); // yalnızca manuel (kampanyalı) saydı
  });

  it("misafir bağışçıya bildirim gitmez, kullanıcıya gider", async () => {
    const guest = setup();
    await applyCollected(guest.deps, don({ userId: null }));
    expect(guest.notes.size).toBe(0);
    const member = setup();
    await applyCollected(member.deps, don());
    expect([...member.notes.values()][0]?.doc.type).toBe("donation_confirmed");
  });
});

describe("başarısız ödeme", () => {
  it("bağış failed olur, kullanıcıya sonuç bildirimi gider, borç değişmez; tekrar çoğalmaz", async () => {
    const { fx, notes, deps } = setup();
    const failed = pay({ kind: "donation", refId: "c1", status: "failed" });
    await applyFailed(deps, failed);
    await applyFailed(deps, failed);
    expect(fx.donations.get("d1")?.status).toBe("failed");
    expect(fx.campaigns.get("c1")?.verifiedTotalMinor).toBe(10_000);
    expect(fx.dues.get("due1")?.paidMinor).toBe(0);
    expect(notes.size).toBe(1);
    expect([...notes.values()][0]?.doc.type).toBe("payment_result");
  });

  it("applyEffects etkileri sırayla uygular", async () => {
    const { fx, deps } = setup();
    const outs = await applyEffects(deps, [
      { type: "collected", payment: pay({ amountMinor: 20_000 }) },
      { type: "failed", payment: pay({ id: "p9", kind: "donation", refId: "c1", status: "failed" }) },
    ]);
    expect(outs.map((o) => o.result)).toEqual(["applied", "applied"]);
    expect(fx.dues.get("due1")?.paidMinor).toBe(20_000);
  });
});

describe("etkinlik ücreti etkisi", () => {
  async function reserved(deps: EffectsDeps) {
    const { registration } = await deps.events.reserveSpot({
      eventId: "ev1", userId: "u1", participant: { name: "Ali", email: "a@b.co" }, nowMs: NOW, reservationMinutes: 15,
    });
    return registration;
  }

  it("ödeme rezervasyonu kesinleştirir ve bildirim gönderir", async () => {
    const { store, notes, deps } = setup();
    const reg = await reserved(deps);
    expect((await applyCollected(deps, pay({ kind: "event_fee", refId: reg.id, amountMinor: 50_000 }))).result).toBe("applied");
    expect(store.allRegistrations("ev1")[0]?.status).toBe("confirmed");
    expect(store.snapshotEvent("ev1")?.confirmedCount).toBe(1);
    expect([...notes.values()][0]?.doc.type).toBe("registration_confirmed");
  });

  it("tekrar uygulama kaydı bozmaz", async () => {
    const { store, deps } = setup();
    const reg = await reserved(deps);
    const p = pay({ kind: "event_fee", refId: reg.id, amountMinor: 50_000 });
    await applyCollected(deps, p);
    expect((await applyCollected(deps, p)).result).toBe("already_applied");
    expect(store.snapshotEvent("ev1")?.confirmedCount).toBe(1);
  });

  it("olmayan kayıt ve onaylanamayan kayıt için iade talebi açılır", async () => {
    const a = setup();
    expect(await applyCollected(a.deps, pay({ kind: "event_fee", refId: "yok" }))).toEqual({
      result: "refund_required", reason: "registration_not_found",
    });
    const b = setup([eventDoc({ capacity: 1 })]);
    const first = await reserved(b.deps);
    await b.svc.expireReservations("ev1", NOW + 20 * 60_000, 15); // süre doldu
    await b.svc.reserveSpot({ eventId: "ev1", userId: "u2", participant: { name: "B", email: "b@c.co" }, nowMs: NOW + 21 * 60_000, reservationMinutes: 15 });
    const out = await applyCollected(b.deps, pay({ kind: "event_fee", refId: first.id, amountMinor: 50_000 }));
    expect(out).toEqual({ result: "refund_required", reason: "registration_not_confirmable" });
    expect(b.refundCalls.length).toBe(1);
  });
});

describe("manuel ödeme + etkiler (uçtan uca)", () => {
  const fin: CallableAuth = { uid: "fin1", token: { role: "finance_manager" } };
  const body = { kind: "membership_due", refId: "due1", userId: "u1", amountMinor: 120_000, receivedAtMs: NOW - DAY, note: "Elden teslim alındı" };

  it("manuel kayıt borcu kapatır, kaynağı 'manual' olur", async () => {
    const { fx, deps } = setup();
    const audit: AuditEntry[] = [];
    const out = await recordManualPaymentHandler(
      { payments: new MemoryPayments(), audit: { write: async (e) => void audit.push(e) }, nowMs: () => NOW, onCollected: (p) => applyCollected(deps, p) },
      fin, body,
    );
    expect(out.effectsApplied).toBe(true);
    expect(fx.dues.get("due1")?.status).toBe("paid");
    expect(fx.duePayments[0]?.source).toBe("manual");
    expect(audit[0]?.after?.["effectsApplied"]).toBe(true);
  });

  it("etki adımı patlarsa ödeme kaydı korunur ve effectsApplied=false döner", async () => {
    const payments = new MemoryPayments();
    const audit: AuditEntry[] = [];
    const out = await recordManualPaymentHandler(
      { payments, audit: { write: async (e) => void audit.push(e) }, nowMs: () => NOW, onCollected: async () => { throw new Error("db kesildi"); } },
      fin, body,
    );
    expect(out.effectsApplied).toBe(false);
    expect(payments.all().length).toBe(1);
    expect(audit[0]?.after?.["effectsApplied"]).toBe(false);
  });
});
