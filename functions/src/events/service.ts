import { DomainError } from "../lib/errors";
import {
  ACTIVE_STATUSES,
  EventDoc,
  Participant,
  RegistrationDoc,
  RegistrationStatus,
  applyDelta,
  canRegistrationTransition,
  counterDelta,
  decideReserve,
  remainingSpots,
} from "./capacity";
import { Tx, TxRunner } from "./store";

const MINUTE_MS = 60_000;

async function requireEvent(tx: Tx, id: string): Promise<EventDoc> {
  const e = await tx.getEvent(id);
  if (!e) throw new DomainError("not-found", "Etkinlik bulunamadı", "event_not_found");
  return e;
}

async function requireRegistration(tx: Tx, id: string): Promise<RegistrationDoc> {
  const r = await tx.getRegistration(id);
  if (!r) throw new DomainError("not-found", "Kayıt bulunamadı", "registration_not_found");
  return r;
}

/** Kayıt durumunu değiştirir, sayaçları günceller; geçersiz geçişi reddeder. */
async function moveRegistration(
  tx: Tx,
  event: EventDoc,
  reg: RegistrationDoc,
  to: RegistrationStatus,
  patch: Partial<Omit<RegistrationDoc, "id">> = {},
): Promise<{ event: EventDoc; reg: RegistrationDoc }> {
  if (!canRegistrationTransition(reg.status, to)) {
    throw new DomainError(
      "failed-precondition",
      `Kayıt ${reg.status} durumundan ${to} durumuna geçemez`,
      "invalid_transition",
    );
  }
  const nextEvent = applyDelta(event, counterDelta(reg.status, to));
  await tx.putEvent(nextEvent);
  await tx.updateRegistration(reg.id, { status: to, ...patch });
  return { event: nextEvent, reg: { ...reg, status: to, ...patch } };
}

/**
 * Boşalan yerleri bekleme listesinden doldurur (sıra: waitlistPosition).
 * Ücretsiz etkinlikte doğrudan onaylanır; ücretliyse ödeme için süreli rezervasyon verilir.
 */
async function promoteFromWaitlist(
  tx: Tx,
  event: EventDoc,
  regs: readonly RegistrationDoc[],
  nowMs: number,
  reservationMinutes: number,
): Promise<{ event: EventDoc; promoted: RegistrationDoc[] }> {
  const waiting = regs
    .filter((r) => r.status === "waitlisted")
    .sort((a, b) => (a.waitlistPosition ?? 0) - (b.waitlistPosition ?? 0));

  let current = event;
  const promoted: RegistrationDoc[] = [];
  for (const w of waiting) {
    if (remainingSpots(current) <= 0) break;
    const free = current.feeMinor === 0;
    const moved = await moveRegistration(
      tx,
      current,
      w,
      free ? "confirmed" : "reserved",
      free
        ? { confirmedAtMs: nowMs, waitlistPosition: null }
        : { reservedUntilMs: nowMs + reservationMinutes * MINUTE_MS, waitlistPosition: null },
    );
    current = moved.event;
    promoted.push(moved.reg);
  }
  return { event: current, promoted };
}

export interface ReserveInput {
  readonly eventId: string;
  readonly userId: string;
  readonly participant: Participant;
  readonly nowMs: number;
  readonly reservationMinutes: number;
}

export interface ReserveResult {
  readonly registration: RegistrationDoc;
}

const REJECT_CODES = {
  already_registered: ["already-exists", "Bu etkinliğe zaten kayıtlısınız"],
  event_not_open: ["failed-precondition", "Etkinlik kayıta açık değil"],
  deadline_passed: ["failed-precondition", "Kayıt süresi doldu"],
  sold_out: ["failed-precondition", "Kontenjan dolu"],
} as const;

export class EventRegistrationService {
  constructor(private readonly runner: TxRunner) {}

  /** Yer ayırır (ücretli), anında onaylar (ücretsiz) veya bekleme listesine yazar. */
  reserveSpot(input: ReserveInput): Promise<ReserveResult> {
    return this.runner.run(async (tx) => {
      const event = await requireEvent(tx, input.eventId);
      const regs = await tx.listRegistrations(input.eventId);
      const hasActive = regs.some(
        (r) => r.userId === input.userId && ACTIVE_STATUSES.includes(r.status),
      );
      const decision = decideReserve(event, input.nowMs, hasActive);

      if (decision.outcome === "rejected") {
        const [code, message] = REJECT_CODES[decision.reason];
        throw new DomainError(code, message, decision.reason);
      }

      const base = {
        eventId: input.eventId,
        userId: input.userId,
        participant: input.participant,
        paymentId: null,
        createdAtMs: input.nowMs,
      };

      if (decision.outcome === "waitlisted") {
        const lastPos = regs.reduce((m, r) => Math.max(m, r.waitlistPosition ?? 0), 0);
        const registration = await tx.createRegistration({
          ...base,
          status: "waitlisted",
          reservedUntilMs: null,
          waitlistPosition: lastPos + 1,
          confirmedAtMs: null,
        });
        return { registration };
      }

      const to: RegistrationStatus = decision.outcome === "reserved" ? "reserved" : "confirmed";
      await tx.putEvent(applyDelta(event, counterDelta(null, to)));
      const registration = await tx.createRegistration({
        ...base,
        status: to,
        reservedUntilMs: to === "reserved" ? input.nowMs + input.reservationMinutes * MINUTE_MS : null,
        waitlistPosition: null,
        confirmedAtMs: to === "confirmed" ? input.nowMs : null,
      });
      return { registration };
    });
  }

  /**
   * Ödeme başarıyla doğrulandığında (webhook) çağrılır. Idempotenttir.
   * Süre dolmuş rezervasyonda yer hâlâ boşsa onaylar; değilse `refund_required` döner
   * (çağıran taraf otomatik iade başlatmalıdır).
   */
  confirmPaid(
    registrationId: string,
    paymentId: string,
    nowMs: number,
  ): Promise<{ outcome: "confirmed" | "already_confirmed" | "refund_required" }> {
    return this.runner.run(async (tx) => {
      const reg = await requireRegistration(tx, registrationId);
      const event = await requireEvent(tx, reg.eventId);

      if (reg.status === "confirmed") return { outcome: "already_confirmed" as const };

      const canConfirm =
        reg.status === "reserved" || (reg.status === "expired" && remainingSpots(event) > 0);
      if (!canConfirm || event.status === "cancelled") {
        return { outcome: "refund_required" as const };
      }
      await moveRegistration(tx, event, reg, "confirmed", {
        paymentId,
        confirmedAtMs: nowMs,
        reservedUntilMs: null,
      });
      return { outcome: "confirmed" as const };
    });
  }

  /** Katılımcı (veya yetkili) iptali. Yer boşalır ve bekleme listesi ilerler. */
  cancelRegistration(input: {
    registrationId: string;
    actorUserId: string;
    actorIsStaff: boolean;
    nowMs: number;
    reservationMinutes: number;
  }): Promise<{ promoted: RegistrationDoc[]; refundRequired: boolean }> {
    return this.runner.run(async (tx) => {
      const reg = await requireRegistration(tx, input.registrationId);
      if (reg.userId !== input.actorUserId && !input.actorIsStaff) {
        throw new DomainError("permission-denied", "Bu kaydı iptal etme yetkiniz yok");
      }
      const event = await requireEvent(tx, reg.eventId);
      const wasConfirmed = reg.status === "confirmed";
      // Firestore kuralı: transaction içinde TÜM okumalar yazmalardan önce yapılmalıdır.
      const allRegs = await tx.listRegistrations(event.id);

      const moved = await moveRegistration(tx, event, reg, "cancelled", {
        reservedUntilMs: null,
        waitlistPosition: null,
      });
      const regs = allRegs.map((r) => (r.id === reg.id ? moved.reg : r));
      const { promoted } = await promoteFromWaitlist(
        tx,
        moved.event,
        regs,
        input.nowMs,
        input.reservationMinutes,
      );
      return {
        promoted,
        refundRequired: wasConfirmed && event.feeMinor > 0 && reg.paymentId !== null,
      };
    });
  }

  /** Zamanlanmış iş: süresi dolan rezervasyonları serbest bırakır, bekleme listesini ilerletir. */
  expireReservations(
    eventId: string,
    nowMs: number,
    reservationMinutes: number,
  ): Promise<{ expired: RegistrationDoc[]; promoted: RegistrationDoc[] }> {
    return this.runner.run(async (tx) => {
      let event = await requireEvent(tx, eventId);
      let regs = await tx.listRegistrations(eventId);
      const expired: RegistrationDoc[] = [];

      for (const r of regs.filter(
        (x) => x.status === "reserved" && x.reservedUntilMs !== null && x.reservedUntilMs <= nowMs,
      )) {
        const moved = await moveRegistration(tx, event, r, "expired");
        event = moved.event;
        expired.push(moved.reg);
      }
      regs = regs.map((r) => expired.find((e) => e.id === r.id) ?? r);

      const { promoted } = await promoteFromWaitlist(tx, event, regs, nowMs, reservationMinutes);
      return { expired, promoted };
    });
  }
}
