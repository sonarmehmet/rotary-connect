import { describe, expect, it } from "vitest";
import { EventRegistrationService } from "../events/service";
import { SimulatedProvider } from "../payments/provider";
import { reconcilePending } from "../payments/reconcile";
import { startPayment } from "../payments/startPayment";
import { processWebhook } from "../payments/webhook";
import { FakeFirestore, fakeClock } from "../testing/fakeFirestore";
import { FirestoreEventTxRunner, FirestorePaymentTxRunner } from "./firestoreStores";

const NOW = 1_800_000_000_000;
const MIN = 60_000;

function eventRow(over: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    title: "Gala",
    capacity: 2,
    reservedCount: 0,
    confirmedCount: 0,
    waitlistEnabled: true,
    status: "published",
    registrationDeadline: fakeClock.fromMs(NOW + 86_400_000),
    feeMinor: 50_000,
    currency: "TRY",
    ...over,
  };
}

const person = { name: "Ali", email: "ali@example.com" };

describe("Firestore adaptörü — etkinlik kaydı", () => {
  function setup() {
    const db = new FakeFirestore();
    db.seed("events", "ev1", eventRow());
    const svc = new EventRegistrationService(new FirestoreEventTxRunner(db, fakeClock));
    const reserve = (userId: string) =>
      svc.reserveSpot({ eventId: "ev1", userId, participant: person, nowMs: NOW, reservationMinutes: 15 });
    return { db, svc, reserve };
  }

  it("kayıt belgesi DATA_MODEL.md alan adlarıyla yazılır (…At Timestamp, …Ms yok)", async () => {
    const { db, reserve } = setup();
    const { registration } = await reserve("u1");
    const raw = db.raw("event_registrations")[0]?.data ?? {};
    expect(raw.status).toBe("reserved");
    expect(raw.eventId).toBe("ev1");
    expect(raw.createdAt).toEqual({ __ts: NOW });
    expect(raw.reservedUntil).toEqual({ __ts: NOW + 15 * MIN });
    expect(Object.keys(raw).some((k) => k.endsWith("Ms"))).toBe(false);
    expect(registration.id).toBe(db.raw("event_registrations")[0]?.id);
  });

  it("etkinlik sayaçları güncellenir, içerik alanlarına dokunulmaz", async () => {
    const { db, reserve } = setup();
    await reserve("u1");
    const ev = db.raw("events")[0]?.data ?? {};
    expect(ev.reservedCount).toBe(1);
    expect(ev.title).toBe("Gala");
    expect(ev.registrationDeadline).toEqual({ __ts: NOW + 86_400_000 });
  });

  it("ödeme onayı, bekleme listesi terfisi ve iptal akışı Firestore kurallarıyla çalışır", async () => {
    const { db, svc, reserve } = setup();
    const a = await reserve("u1");
    const b = await reserve("u2");
    const c = await reserve("u3"); // bekleme listesi
    expect(c.registration.status).toBe("waitlisted");
    expect((await svc.confirmPaid(a.registration.id, "pay1", NOW + 1)).outcome).toBe("confirmed");
    const out = await svc.cancelRegistration({
      registrationId: b.registration.id, actorUserId: "u2", actorIsStaff: false, nowMs: NOW + 2, reservationMinutes: 15,
    });
    expect(out.promoted.map((p) => p.id)).toEqual([c.registration.id]);
    const ev = db.raw("events")[0]?.data ?? {};
    expect(ev.confirmedCount).toBe(1);
    expect(ev.reservedCount).toBe(1);
    const promoted = db.raw("event_registrations").find((r) => r.id === c.registration.id)?.data;
    expect(promoted?.status).toBe("reserved");
    expect(promoted?.waitlistPosition).toBe(null);
  });

  it("süre dolumu mutabakatı çalışır", async () => {
    const { db, svc, reserve } = setup();
    await reserve("u1");
    const r = await svc.expireReservations("ev1", NOW + 20 * MIN, 15);
    expect(r.expired.length).toBe(1);
    expect(db.raw("events")[0]?.data.reservedCount).toBe(0);
  });
});

describe("Firestore adaptörü — ödemeler", () => {
  async function seed() {
    const db = new FakeFirestore();
    const runner = new FirestorePaymentTxRunner(db, fakeClock);
    const provider = new SimulatedProvider();
    const r = await startPayment(runner, provider, {
      kind: "donation", refId: "c1", userId: "u1",
      amount: { amountMinor: 25_000, currency: "TRY" },
      clientKey: "client-key-1", description: "t", nowMs: NOW, mode: "simulation", newId: () => "x",
    });
    return { db, runner, provider, ref: r.payment.providerRef as string, payment: r.payment };
  }

  it("ödeme belgesi doğru alan adlarıyla yazılır ve pending olur", async () => {
    const { db, ref } = await seed();
    const raw = db.raw("payments")[0]?.data ?? {};
    expect(raw.status).toBe("pending");
    expect(raw.providerRef).toBe(ref);
    expect(raw.simulated).toBe(true);
    expect(raw.createdAt).toEqual({ __ts: NOW });
    expect(raw.succeededAt).toBe(null);
    expect(raw.kind).toBe("donation");
    expect(Object.keys(raw).some((k) => k.endsWith("Ms"))).toBe(false);
  });

  it("aynı anahtarla tekrar çağrı yeni belge oluşturmaz", async () => {
    const { db, runner, provider } = await seed();
    await startPayment(runner, provider, {
      kind: "donation", refId: "c1", userId: "u1",
      amount: { amountMinor: 25_000, currency: "TRY" },
      clientKey: "client-key-1", description: "t", nowMs: NOW, mode: "simulation", newId: () => "y",
    });
    expect(db.raw("payments").length).toBe(1);
  });

  it("webhook ödemeyi kapatır; tekrar gelen bildirim yok sayılır", async () => {
    const { db, runner, ref } = await seed();
    const ev = { providerRef: ref, status: "succeeded" as const, amountMinor: 25_000, currency: "TRY" };
    const first = await processWebhook(runner, { event: ev, signatureValid: true, nowMs: NOW + 5 });
    const second = await processWebhook(runner, { event: ev, signatureValid: true, nowMs: NOW + 6 });
    expect(first.result).toBe("applied");
    expect(second.result).toBe("ignored");
    const raw = db.raw("payments")[0]?.data ?? {};
    expect(raw.status).toBe("succeeded");
    expect(raw.succeededAt).toEqual({ __ts: NOW + 5 });
  });

  it("mutabakat tarih filtresiyle bekleyen ödemeleri bulur", async () => {
    const { db, runner, provider, ref } = await seed();
    provider.simulateResult(ref, "succeeded");
    const rep = await reconcilePending(runner, provider, {
      nowMs: NOW + 15 * MIN, olderThanMs: 10 * MIN, batchSize: 10, expireAfterMs: 60 * MIN,
    });
    expect(rep.applied).toBe(1);
    expect(db.raw("payments")[0]?.data.status).toBe("succeeded");
  });
});
