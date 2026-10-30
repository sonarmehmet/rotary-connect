/**
 * Etkinlik kontenjanı: SAF (yan etkisiz) kurallar. Veritabanı erişimi service.ts'te.
 *
 * Değişmez (invariant): remainingSpots > 0 iken bekleme listesi BOŞTUR. Bu, bir yer
 * açıldığında aynı transaction içinde bekleme listesinden terfi yapılarak sağlanır;
 * böylece yeni gelen kişi sıradakilerin önüne geçemez.
 */
export type EventStatus = "draft" | "published" | "cancelled" | "completed";

export type RegistrationStatus =
  | "reserved"
  | "confirmed"
  | "waitlisted"
  | "cancelled"
  | "expired"
  | "refunded";

/** Kontenjanı veya bekleme sırasını tutan (aktif) kayıt durumları. */
export const ACTIVE_STATUSES: readonly RegistrationStatus[] = [
  "reserved",
  "confirmed",
  "waitlisted",
];

export interface EventDoc {
  readonly id: string;
  readonly capacity: number;
  readonly reservedCount: number;
  readonly confirmedCount: number;
  readonly waitlistEnabled: boolean;
  readonly status: EventStatus;
  readonly registrationDeadlineMs: number;
  readonly feeMinor: number;
  readonly currency: string;
}

export interface Participant {
  readonly name: string;
  readonly email: string;
  readonly phone?: string;
}

export interface RegistrationDoc {
  readonly id: string;
  readonly eventId: string;
  readonly userId: string;
  readonly participant: Participant;
  readonly status: RegistrationStatus;
  readonly paymentId: string | null;
  readonly reservedUntilMs: number | null;
  readonly waitlistPosition: number | null;
  readonly createdAtMs: number;
  readonly confirmedAtMs: number | null;
}

export function remainingSpots(e: EventDoc): number {
  return Math.max(0, e.capacity - e.confirmedCount - e.reservedCount);
}

export type ReserveDecision =
  | { outcome: "reserved" }
  | { outcome: "confirmed_free" }
  | { outcome: "waitlisted" }
  | {
      outcome: "rejected";
      reason: "event_not_open" | "deadline_passed" | "sold_out" | "already_registered";
    };

export function decideReserve(
  e: EventDoc,
  nowMs: number,
  hasActiveRegistration: boolean,
): ReserveDecision {
  if (hasActiveRegistration) return { outcome: "rejected", reason: "already_registered" };
  if (e.status !== "published") return { outcome: "rejected", reason: "event_not_open" };
  if (nowMs > e.registrationDeadlineMs) {
    return { outcome: "rejected", reason: "deadline_passed" };
  }
  if (remainingSpots(e) > 0) {
    return e.feeMinor === 0 ? { outcome: "confirmed_free" } : { outcome: "reserved" };
  }
  return e.waitlistEnabled
    ? { outcome: "waitlisted" }
    : { outcome: "rejected", reason: "sold_out" };
}

const ALLOWED: Record<RegistrationStatus, readonly RegistrationStatus[]> = {
  reserved: ["confirmed", "cancelled", "expired"],
  confirmed: ["cancelled", "refunded"],
  waitlisted: ["reserved", "confirmed", "cancelled"],
  cancelled: [],
  expired: ["confirmed"], // ödeme süre dolduktan sonra başarılı geldiyse (yer varsa)
  refunded: [],
};

export function canRegistrationTransition(
  from: RegistrationStatus,
  to: RegistrationStatus,
): boolean {
  return ALLOWED[from].includes(to);
}

export interface CounterDelta {
  readonly reserved: number;
  readonly confirmed: number;
}

/** Bir kayıt durumu değişiminin etkinlik sayaçlarına etkisi. `from` null = yeni kayıt. */
export function counterDelta(
  from: RegistrationStatus | null,
  to: RegistrationStatus,
): CounterDelta {
  const reservedOf = (s: RegistrationStatus | null): number => (s === "reserved" ? 1 : 0);
  const confirmedOf = (s: RegistrationStatus | null): number => (s === "confirmed" ? 1 : 0);
  return {
    reserved: reservedOf(to) - reservedOf(from),
    confirmed: confirmedOf(to) - confirmedOf(from),
  };
}

export function applyDelta(e: EventDoc, d: CounterDelta): EventDoc {
  const reservedCount = e.reservedCount + d.reserved;
  const confirmedCount = e.confirmedCount + d.confirmed;
  if (reservedCount < 0 || confirmedCount < 0) {
    throw new Error("Sayaç negatif olamaz (tutarsız durum)");
  }
  return { ...e, reservedCount, confirmedCount };
}
