import { describe, expect, it } from "vitest";
import { EventDoc } from "../events/capacity";
import { EventRegistrationService } from "../events/service";
import { MemoryEffects } from "../testing/memoryEffects";
import { MemoryStore } from "../testing/memoryStore";
import { applyCollected } from "./effects";
import { FakeFirestore, fakeClock } from "../testing/fakeFirestore";
import { FirestoreRefundSweepSource } from "../adapters/adminFirestore";
import { RefundEffectsDeps, RefundSweepSource, applyRefundEffects, sweepRefundEffects } from "./refundEffects";
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

function setup() {
  const fx = new MemoryEffects();
  const ev: EventDoc = {
    id: "ev1", capacity: 2, reservedCount: 0, confirmedCount: 0, waitlistEnabled: true, status: "published",
    registrationDeadlineMs: NOW + DAY, feeMinor: 50_000, currency: "TRY",
  };
  const store = new MemoryStore([ev]);
  const svc = new EventRegistrationService(store);
  const deps: RefundEffectsDeps = { runner: fx, events: svc, reservationMinutes: 15, nowMs: () => NOW };
  fx.dues.set("due1", {
    id: "due1", userId: "u1", currency: "TRY", amountMinor: 120_000, paidMinor: 120_000, dueDateMs: NOW + 30 * DAY,
    cancelled: false, refunded: false, allowPartial: true, status: "paid",
  });
  fx.campaigns.set("c1", { verifiedTotalMinor: 100_000, donorCount: 3 });
  fx.donations.set("d1", { id: "d1", paymentId: "p2", status: "succeeded" });
  return { fx, svc, store, deps };
}

describe("iade etkileri — aidat", () => {
  it("kısmi iade borcu yeniden açar (ödenen düşer, durum türetilir)", async () => {
    const { fx, deps } = setup();
    expect(await applyRefundEffects(deps, pay({}), "r1", 30_000, false)).toBe("applied");
    expect(fx.dues.get("due1")?.paidMinor).toBe(90_000);
    expect(fx.dues.get("due1")?.status).toBe("partially_paid");
  });

  it("tam iade (yanlış ödeme) borcu tamamen açar", async () => {
    const { fx, deps } = setup();
    await applyRefundEffects(deps, pay({}), "r1", 120_000, true);
    expect(fx.dues.get("due1")?.paidMinor).toBe(0);
    expect(fx.dues.get("due1")?.status).toBe("unpaid");
  });

  it("aynı iade için tekrar çağrı ikinci kez düşmez", async () => {
    const { fx, deps } = setup();
    await applyRefundEffects(deps, pay({}), "r1", 30_000, false);
    expect(await applyRefundEffects(deps, pay({}), "r1", 30_000, false)).toBe("already_applied");
    expect(fx.dues.get("due1")?.paidMinor).toBe(90_000);
  });

  it("borç yoksa iade yine de işaretlenir, hata vermez", async () => {
    const { fx, deps } = setup();
    fx.dues.clear();
    expect(await applyRefundEffects(deps, pay({}), "r1", 10_000, false)).toBe("applied");
  });
});

describe("iade etkileri — bağış", () => {
  const donation = (over: Partial<PaymentDoc> = {}) =>
    pay({ id: "p2", kind: "donation", refId: "c1", amountMinor: 40_000, ...over });

  it("kısmi iade kampanya toplamını düşürür, bağışçı sayısı aynı kalır", async () => {
    const { fx, deps } = setup();
    await applyRefundEffects(deps, donation(), "r1", 10_000, false);
    expect(fx.campaigns.get("c1")).toEqual({ verifiedTotalMinor: 90_000, donorCount: 3 });
    expect(fx.donations.get("d1")?.status).toBe("partially_refunded");
  });

  it("tam iade bağışçı sayısını da düşürür", async () => {
    const { fx, deps } = setup();
    await applyRefundEffects(deps, donation(), "r1", 40_000, true);
    expect(fx.campaigns.get("c1")).toEqual({ verifiedTotalMinor: 60_000, donorCount: 2 });
    expect(fx.donations.get("d1")?.status).toBe("refunded");
  });

  it("simülasyon bağışı kampanya toplamına hiç girmediği için toplam değişmez", async () => {
    const { fx, deps } = setup();
    await applyRefundEffects(deps, donation({ simulated: true }), "r1", 40_000, true);
    expect(fx.campaigns.get("c1")).toEqual({ verifiedTotalMinor: 100_000, donorCount: 3 });
    expect(fx.donations.get("d1")?.status).toBe("refunded");
  });

  it("toplam eksiye düşmez", async () => {
    const { fx, deps } = setup();
    fx.campaigns.set("c1", { verifiedTotalMinor: 5_000, donorCount: 0 });
    await applyRefundEffects(deps, donation(), "r1", 40_000, true);
    expect(fx.campaigns.get("c1")).toEqual({ verifiedTotalMinor: 0, donorCount: 0 });
  });
});

describe("iade etkileri — etkinlik ücreti", () => {
  async function confirmed() {
    const s = setup();
    const r = await s.svc.reserveSpot({
      eventId: "ev1", userId: "u1", participant: { name: "Ali", email: "a@b.co" }, nowMs: NOW, reservationMinutes: 15,
    });
    await s.svc.confirmPaid(r.registration.id, "p3", NOW + 1);
    return { ...s, regId: r.registration.id };
  }

  it("tam iade kaydı iptal eder ve yeri boşaltır", async () => {
    const { deps, store, regId } = await confirmed();
    const payment = pay({ id: "p3", kind: "event_fee", refId: regId, amountMinor: 50_000 });
    expect(await applyRefundEffects(deps, payment, "r1", 50_000, true)).toBe("applied");
    expect((await store.run((tx) => tx.getRegistration(regId)))?.status).toBe("cancelled");
    expect((await store.run((tx) => tx.getEvent("ev1")))?.confirmedCount).toBe(0);
  });

  it("kısmi iade kaydı iptal ETMEZ", async () => {
    const { deps, store, regId } = await confirmed();
    const payment = pay({ id: "p3", kind: "event_fee", refId: regId, amountMinor: 50_000 });
    await applyRefundEffects(deps, payment, "r1", 10_000, false);
    expect((await store.run((tx) => tx.getRegistration(regId)))?.status).toBe("confirmed");
  });

  it("kayıt zaten yoksa iade hata vermez; tekrar çağrı işaretlenmiş olur", async () => {
    const { deps } = setup();
    const payment = pay({ id: "p3", kind: "event_fee", refId: "yok", amountMinor: 50_000 });
    expect(await applyRefundEffects(deps, payment, "r1", 50_000, true)).toBe("applied");
    expect(await applyRefundEffects(deps, payment, "r1", 50_000, true)).toBe("already_applied");
  });
});

describe("tahsilat → iade döngüsü", () => {
  it("manuel hatalı ödeme: tahsilat borcu kapatır, iade yeniden açar", async () => {
    const s = setup();
    s.fx.dues.set("due1", {
      id: "due1", userId: "u1", currency: "TRY", amountMinor: 120_000, paidMinor: 0, dueDateMs: NOW + 30 * DAY,
      cancelled: false, refunded: false, allowPartial: true, status: "unpaid",
    });
    const p = pay({ manual: true, provider: "manual" });
    await applyCollected(
      {
        runner: s.fx, events: s.svc, nowMs: () => NOW,
        notifications: { createIfAbsent: async () => undefined },
        refunds: { request: async () => undefined },
      },
      p,
    );
    expect(s.fx.dues.get("due1")?.status).toBe("paid");
    await applyRefundEffects(s.deps, p, "r1", 120_000, true);
    expect(s.fx.dues.get("due1")?.status).toBe("unpaid");
  });
});

describe("iade etkisi taraması", () => {
  it("uygulanmamış iadeyi yakalar, uygulananı çift düşmez; hata diğerlerini durdurmaz", async () => {
    const { fx, deps } = setup();
    const rows = [
      { refundId: "r1", payment: pay({}), refundMinor: 30_000, full: false },
      { refundId: "r2", payment: pay({ id: "p9", refId: "yok-borc" }), refundMinor: 1_000, full: false },
    ];
    const source: RefundSweepSource = { listSucceededSince: async () => rows };
    const first = await sweepRefundEffects(source, deps, 0, 10);
    expect(first).toEqual({ checked: 2, applied: 2, errors: 0 });
    expect(fx.dues.get("due1")?.paidMinor).toBe(90_000);
    const second = await sweepRefundEffects(source, deps, 0, 10);
    expect(second.applied).toBe(0);
    expect(fx.dues.get("due1")?.paidMinor).toBe(90_000);

    const failing: RefundSweepSource = {
      listSucceededSince: async () => [
        { refundId: "x", payment: { ...pay({}), get kind(): never { throw new Error("bozuk"); } } as unknown as PaymentDoc, refundMinor: 1, full: false },
        { refundId: "r3", payment: pay({}), refundMinor: 10_000, full: false },
      ],
    };
    const third = await sweepRefundEffects(failing, deps, 0, 10);
    expect(third).toEqual({ checked: 2, applied: 1, errors: 1 });
    expect(fx.dues.get("due1")?.paidMinor).toBe(80_000);
  });

  it("Firestore kaynağı: kümülatif tam iadeyi doğru hesaplar, başarısız iadeyi atlar", async () => {
    const db = new FakeFirestore();
    db.seed("payments", "p1", {
      kind: "donation", refId: "c1", userId: "u1", amountMinor: 50_000, currency: "TRY", status: "refunded",
      provider: "simulation", providerRef: null, simulated: false, idempotencyKey: "k", manual: false,
      recordedBy: null, note: null, refundedMinor: 50_000, createdAt: fakeClock.fromMs(NOW),
      updatedAt: fakeClock.fromMs(NOW), succeededAt: fakeClock.fromMs(NOW), failureCode: null, flag: null,
    });
    const refund = (amount: number, t: number, status = "succeeded") => ({
      paymentId: "p1", kind: "donation", amountMinor: amount, currency: "TRY", reason: "x", status,
      requestedBy: "fin1", createdAt: fakeClock.fromMs(t),
    });
    db.seed("refunds", "a", refund(20_000, NOW + 1));
    db.seed("refunds", "b", refund(30_000, NOW + 2));
    db.seed("refunds", "c", refund(5_000, NOW + 3, "failed"));
    const rows = await new FirestoreRefundSweepSource(db, fakeClock).listSucceededSince(NOW, 10);
    const byId = Object.fromEntries(rows.map((r) => [r.refundId, r]));
    expect(Object.keys(byId).sort()).toEqual(["a", "b"]);
    expect(byId["a"]).toMatchObject({ refundMinor: 20_000, full: false });
    expect(byId["b"]).toMatchObject({ refundMinor: 30_000, full: true });
  });
});
