import { describe, expect, it } from "vitest";
import { EventRegistrationService } from "../events/service";
import { applyCollected, applyFailed, EffectsDeps } from "../payments/effects";
import { PaymentDoc } from "../payments/repo";
import { FakeFirestore, fakeClock } from "../testing/fakeFirestore";
import { MemoryStore } from "../testing/memoryStore";
import { FirestoreEffectsTxRunner } from "./firestoreEffects";

const NOW = 1_800_000_000_000;
const DAY = 86_400_000;

function pay(over: Partial<PaymentDoc>): PaymentDoc {
  return {
    id: "p1", kind: "membership_due", refId: "due1", userId: "u1", amountMinor: 100_000, currency: "TRY",
    status: "succeeded", provider: "iyzico", providerRef: "R1", simulated: false, idempotencyKey: "k",
    manual: false, recordedBy: null, note: null, refundedMinor: 0, createdAtMs: NOW, updatedAtMs: NOW,
    succeededAtMs: NOW, failureCode: null, flag: null, ...over,
  };
}

function setup() {
  const db = new FakeFirestore();
  db.seed("membership_dues", "due1", {
    userId: "u1", currency: "TRY", amountMinor: 100_000, paidMinor: 0, dueDate: fakeClock.fromMs(NOW + DAY),
    status: "unpaid", allowPartial: false,
  });
  db.seed("donation_campaigns", "c1", { verifiedTotalMinor: 5_000, donorCount: 1 });
  db.seed("donations", "d1", { paymentId: "p2", status: "pending", campaignId: "c1" });
  const deps: EffectsDeps = {
    runner: new FirestoreEffectsTxRunner(db, fakeClock),
    events: new EventRegistrationService(new MemoryStore([])),
    notifications: { createIfAbsent: async () => undefined },
    refunds: { request: async () => undefined },
    nowMs: () => NOW,
  };
  return { db, deps };
}

describe("Firestore etki adaptörü", () => {
  it("aidat ödemesi borcu kapatır, bağ kaydı ve işaretçi yazar; tekrar etkisizdir", async () => {
    const { db, deps } = setup();
    expect(await applyCollected(deps, pay({}))).toEqual({ result: "applied" });
    expect(db.raw("membership_dues")[0]?.data["paidMinor"]).toBe(100_000);
    expect(db.raw("membership_dues")[0]?.data["status"]).toBe("paid");
    expect(db.raw("membership_due_payments").length).toBe(1);
    expect(db.raw("effect_markers").length).toBe(1);
    expect(await applyCollected(deps, pay({}))).toEqual({ result: "already_applied" });
    expect(db.raw("membership_due_payments").length).toBe(1);
    expect(db.raw("membership_dues")[0]?.data["paidMinor"]).toBe(100_000);
  });

  it("bağış başarılı olunca kayıt ve kampanya toplamı güncellenir; simülasyon toplama girmez", async () => {
    const { db, deps } = setup();
    await applyCollected(deps, pay({ id: "p2", kind: "donation", refId: "c1", amountMinor: 2_500 }));
    expect(db.raw("donations")[0]?.data["status"]).toBe("succeeded");
    expect(db.raw("donation_campaigns")[0]?.data["verifiedTotalMinor"]).toBe(7_500);
    expect(db.raw("donation_campaigns")[0]?.data["donorCount"]).toBe(2);

    const s = setup();
    await applyCollected(s.deps, pay({ id: "p2", kind: "donation", refId: "c1", amountMinor: 2_500, simulated: true }));
    expect(s.db.raw("donation_campaigns")[0]?.data["verifiedTotalMinor"]).toBe(5_000);
  });

  it("başarısız bağış kaydını failed yapar", async () => {
    const { db, deps } = setup();
    await applyFailed(deps, pay({ id: "p2", kind: "donation", refId: "c1", status: "failed" }));
    expect(db.raw("donations")[0]?.data["status"]).toBe("failed");
  });

  it("fazla ödeme iade talebine döner ve borç değişmez", async () => {
    const { db, deps } = setup();
    const out = await applyCollected(deps, pay({ amountMinor: 150_000 }));
    expect(out).toEqual({ result: "refund_required", reason: "overpayment" });
    expect(db.raw("membership_dues")[0]?.data["paidMinor"]).toBe(0);
  });
});
