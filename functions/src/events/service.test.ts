import { describe, expect, it } from "vitest";
import { DomainError } from "../lib/errors";
import { MemoryStore } from "../testing/memoryStore";
import { EventDoc, counterDelta, decideReserve, remainingSpots } from "./capacity";
import { EventRegistrationService } from "./service";

const NOW = 1_000_000_000_000;
const MIN = 15;

function makeEvent(over: Partial<EventDoc> = {}): EventDoc {
  return {
    id: "ev1",
    capacity: 3,
    reservedCount: 0,
    confirmedCount: 0,
    waitlistEnabled: true,
    status: "published",
    registrationDeadlineMs: NOW + 86_400_000,
    feeMinor: 50_000,
    currency: "TRY",
    ...over,
  };
}

const person = (n: number) => ({ name: `Kişi ${n}`, email: `k${n}@example.com` });

function setup(over: Partial<EventDoc> = {}) {
  const store = new MemoryStore([makeEvent(over)]);
  const svc = new EventRegistrationService(store);
  const reserve = (userId: string, nowMs = NOW) =>
    svc.reserveSpot({
      eventId: "ev1",
      userId,
      participant: person(1),
      nowMs,
      reservationMinutes: MIN,
    });
  return { store, svc, reserve };
}

async function codeOf(p: Promise<unknown>): Promise<string | undefined> {
  try {
    await p;
    return undefined;
  } catch (e) {
    return e instanceof DomainError ? `${e.code}:${e.reason}` : "other";
  }
}

describe("capacity (saf kurallar)", () => {
  it("kalan yer hesabı", () => {
    expect(remainingSpots(makeEvent({ confirmedCount: 1, reservedCount: 1 }))).toBe(1);
    expect(remainingSpots(makeEvent({ confirmedCount: 3 }))).toBe(0);
  });

  it("karar: ücretli rezerve, ücretsiz onay, dolu bekleme/ret", () => {
    expect(decideReserve(makeEvent(), NOW, false).outcome).toBe("reserved");
    expect(decideReserve(makeEvent({ feeMinor: 0 }), NOW, false).outcome).toBe("confirmed_free");
    const full = makeEvent({ confirmedCount: 3 });
    expect(decideReserve(full, NOW, false).outcome).toBe("waitlisted");
    expect(decideReserve({ ...full, waitlistEnabled: false }, NOW, false)).toEqual({
      outcome: "rejected",
      reason: "sold_out",
    });
    expect(decideReserve(makeEvent(), NOW, true)).toEqual({
      outcome: "rejected",
      reason: "already_registered",
    });
    expect(decideReserve(makeEvent({ status: "cancelled" }), NOW, false)).toEqual({
      outcome: "rejected",
      reason: "event_not_open",
    });
    expect(decideReserve(makeEvent(), NOW + 999_999_999, false)).toEqual({
      outcome: "rejected",
      reason: "deadline_passed",
    });
  });

  it("sayaç etkisi", () => {
    expect(counterDelta(null, "reserved")).toEqual({ reserved: 1, confirmed: 0 });
    expect(counterDelta("reserved", "confirmed")).toEqual({ reserved: -1, confirmed: 1 });
    expect(counterDelta("confirmed", "cancelled")).toEqual({ reserved: 0, confirmed: -1 });
    expect(counterDelta("reserved", "expired")).toEqual({ reserved: -1, confirmed: 0 });
    expect(counterDelta(null, "waitlisted")).toEqual({ reserved: 0, confirmed: 0 });
  });
});

describe("EventRegistrationService", () => {
  it("ücretli etkinlikte yer ayırır ve süre verir", async () => {
    const { store, reserve } = setup();
    const { registration } = await reserve("u1");
    expect(registration.status).toBe("reserved");
    expect(registration.reservedUntilMs).toBe(NOW + MIN * 60_000);
    expect(store.snapshotEvent("ev1")?.reservedCount).toBe(1);
  });

  it("ücretsiz etkinlikte doğrudan onaylar", async () => {
    const { store, reserve } = setup({ feeMinor: 0 });
    const { registration } = await reserve("u1");
    expect(registration.status).toBe("confirmed");
    expect(store.snapshotEvent("ev1")?.confirmedCount).toBe(1);
  });

  it("aynı kullanıcı iki kez kayıt olamaz", async () => {
    const { reserve } = setup();
    await reserve("u1");
    expect(await codeOf(reserve("u1"))).toBe("already-exists:already_registered");
  });

  it("kontenjan dolunca bekleme listesi, sırayla numaralanır", async () => {
    const { reserve } = setup({ capacity: 1 });
    await reserve("u1");
    const a = await reserve("u2");
    const b = await reserve("u3");
    expect(a.registration.status).toBe("waitlisted");
    expect(a.registration.waitlistPosition).toBe(1);
    expect(b.registration.waitlistPosition).toBe(2);
  });

  it("bekleme listesi kapalıysa dolu hatası verir", async () => {
    const { reserve } = setup({ capacity: 1, waitlistEnabled: false });
    await reserve("u1");
    expect(await codeOf(reserve("u2"))).toBe("failed-precondition:sold_out");
  });

  it("EŞZAMANLI kayıt: kontenjan asla aşılmaz (20 istek, 3 yer)", async () => {
    const { store, reserve } = setup({ capacity: 3, waitlistEnabled: false });
    const results = await Promise.allSettled(
      Array.from({ length: 20 }, (_, i) => reserve(`u${i}`)),
    );
    const ok = results.filter((r) => r.status === "fulfilled").length;
    const ev = store.snapshotEvent("ev1");
    expect(ok).toBe(3);
    expect(ev?.reservedCount).toBe(3);
    expect(store.allRegistrations("ev1").filter((r) => r.status === "reserved").length).toBe(3);
    expect(store.retries > 0).toBe(true); // gerçekten çakışma yaşandı ve çözüldü
  });

  it("EŞZAMANLI: aynı kullanıcı 5 kez paralel denerse tek kayıt oluşur", async () => {
    const { store, reserve } = setup();
    await Promise.allSettled(Array.from({ length: 5 }, () => reserve("same")));
    expect(store.allRegistrations("ev1").length).toBe(1);
    expect(store.snapshotEvent("ev1")?.reservedCount).toBe(1);
  });

  it("ödeme onayı rezervasyonu kesinleştirir ve idempotenttir", async () => {
    const { store, svc, reserve } = setup();
    const { registration } = await reserve("u1");
    expect((await svc.confirmPaid(registration.id, "pay1", NOW + 1000)).outcome).toBe("confirmed");
    expect((await svc.confirmPaid(registration.id, "pay1", NOW + 2000)).outcome).toBe(
      "already_confirmed",
    );
    const ev = store.snapshotEvent("ev1");
    expect(ev?.reservedCount).toBe(0);
    expect(ev?.confirmedCount).toBe(1);
  });

  it("süre dolunca yer serbest kalır ve bekleme listesinden terfi eder", async () => {
    const { store, svc, reserve } = setup({ capacity: 1 });
    const first = await reserve("u1");
    const waiting = await reserve("u2");
    const later = NOW + (MIN + 1) * 60_000;
    const r = await svc.expireReservations("ev1", later, MIN);
    expect(r.expired.map((x) => x.id)).toEqual([first.registration.id]);
    expect(r.promoted.map((x) => x.id)).toEqual([waiting.registration.id]);
    expect(r.promoted[0]?.status).toBe("reserved");
    expect(r.promoted[0]?.reservedUntilMs).toBe(later + MIN * 60_000);
    const ev = store.snapshotEvent("ev1");
    expect(ev?.reservedCount).toBe(1);
  });

  it("süre dolduktan sonra gelen başarılı ödeme: yer varsa onaylanır, yoksa iade gerekir", async () => {
    const a = setup({ capacity: 2 });
    const r1 = await a.reserve("u1");
    await a.svc.expireReservations("ev1", NOW + 20 * 60_000, MIN);
    expect((await a.svc.confirmPaid(r1.registration.id, "p", NOW + 21 * 60_000)).outcome).toBe(
      "confirmed",
    );

    const b = setup({ capacity: 1, waitlistEnabled: true });
    const first = await b.reserve("u1");
    await b.reserve("u2"); // bekleme listesi
    await b.svc.expireReservations("ev1", NOW + 20 * 60_000, MIN); // u2 terfi etti, yer doldu
    expect((await b.svc.confirmPaid(first.registration.id, "p", NOW + 21 * 60_000)).outcome).toBe(
      "refund_required",
    );
  });

  it("onaylı kaydı iptal: yer boşalır, sıradaki terfi eder, iade gerekir", async () => {
    const { store, svc, reserve } = setup({ capacity: 1 });
    const first = await reserve("u1");
    await svc.confirmPaid(first.registration.id, "pay1", NOW + 1);
    const waiting = await reserve("u2");

    const out = await svc.cancelRegistration({
      registrationId: first.registration.id,
      actorUserId: "u1",
      actorIsStaff: false,
      nowMs: NOW + 5,
      reservationMinutes: MIN,
    });
    expect(out.refundRequired).toBe(true);
    expect(out.promoted.map((p) => p.id)).toEqual([waiting.registration.id]);
    const ev = store.snapshotEvent("ev1");
    expect(ev?.confirmedCount).toBe(0);
    expect(ev?.reservedCount).toBe(1);
  });

  it("başkasının kaydı iptal edilemez; personel edebilir", async () => {
    const { svc, reserve } = setup();
    const { registration } = await reserve("u1");
    const base = {
      registrationId: registration.id,
      nowMs: NOW,
      reservationMinutes: MIN,
    };
    expect(
      await codeOf(svc.cancelRegistration({ ...base, actorUserId: "intruder", actorIsStaff: false })),
    ).toBe("permission-denied:undefined");
    await svc.cancelRegistration({ ...base, actorUserId: "staff", actorIsStaff: true });
  });

  it("iptal edilmiş kayıt tekrar iptal edilemez; iptalden sonra yeniden kayıt olunabilir", async () => {
    const { svc, reserve } = setup();
    const { registration } = await reserve("u1");
    const input = {
      registrationId: registration.id,
      actorUserId: "u1",
      actorIsStaff: false,
      nowMs: NOW,
      reservationMinutes: MIN,
    };
    await svc.cancelRegistration(input);
    expect(await codeOf(svc.cancelRegistration(input))).toBe(
      "failed-precondition:invalid_transition",
    );
    expect((await reserve("u1")).registration.status).toBe("reserved");
  });

  it("ücretsiz etkinlikte terfi eden doğrudan onaylanır", async () => {
    const { svc, reserve } = setup({ capacity: 1, feeMinor: 0 });
    const first = await reserve("u1");
    const waiting = await reserve("u2");
    expect(waiting.registration.status).toBe("waitlisted");
    const out = await svc.cancelRegistration({
      registrationId: first.registration.id,
      actorUserId: "u1",
      actorIsStaff: false,
      nowMs: NOW,
      reservationMinutes: MIN,
    });
    expect(out.promoted[0]?.status).toBe("confirmed");
    expect(out.refundRequired).toBe(false);
  });
});
