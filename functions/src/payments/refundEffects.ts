import { deriveDueStatus } from "../dues/dues";
import { EventRegistrationService } from "../events/service";
import { DomainError } from "../lib/errors";
import { EffectsTxRunner } from "./effects";
import { PaymentDoc } from "./repo";

/**
 * İadenin iş kayıtlarına yansıması ("yanlış işlem" düzeltmesi). Para iadesi kaydedildikten SONRA
 * çalışır; her iade için `refunded:<refundId>` işaretiyle İDEMPOTENTTİR (tekrar çağrı ikinci kez
 * düşmez). Etkiler:
 * - Aidat: ödenen tutar iade kadar düşer, borç yeniden açılır (durum alanlardan türetilir).
 * - Bağış: bağış kaydı `partially_refunded`/`refunded` olur; simülasyon DEĞİLSE kampanyanın
 *   doğrulanmış toplamı iade kadar düşer, tam iadede bağışçı sayısı 1 azalır.
 * - Etkinlik ücreti: TAM iadede kayıt iptal edilir, yer boşalır, bekleme listesi ilerler.
 */
export interface RefundEffectsDeps {
  readonly runner: EffectsTxRunner;
  readonly events: EventRegistrationService;
  readonly reservationMinutes: number;
  readonly nowMs: () => number;
}

export type RefundEffectOutcome = "applied" | "already_applied";

export async function applyRefundEffects(
  deps: RefundEffectsDeps,
  payment: PaymentDoc,
  refundId: string,
  refundMinor: number,
  full: boolean,
): Promise<RefundEffectOutcome> {
  const nowMs = deps.nowMs();
  if (payment.kind === "event_fee") {
    return refundEventFee(deps, payment, refundId, refundMinor, full, nowMs);
  }
  return deps.runner.run(async (tx): Promise<RefundEffectOutcome> => {
    const key = `refunded:${refundId}`;
    if (await tx.hasMarker(key)) return "already_applied";
    if (payment.kind === "membership_due") {
      const due = await tx.getDue(payment.refId);
      if (due) {
        const paidMinor = Math.max(0, due.paidMinor - refundMinor);
        tx.updateDue(due.id, { paidMinor, status: deriveDueStatus({ ...due, paidMinor }, nowMs) });
      }
    } else {
      const donation = await tx.getDonationByPayment(payment.id);
      const campaign = payment.refId === "general" ? null : await tx.getCampaign(payment.refId);
      if (donation) tx.updateDonation(donation.id, { status: full ? "refunded" : "partially_refunded" });
      if (campaign && !payment.simulated) {
        tx.updateCampaign(payment.refId, {
          verifiedTotalMinor: Math.max(0, campaign.verifiedTotalMinor - refundMinor),
          donorCount: Math.max(0, campaign.donorCount - (full ? 1 : 0)),
        });
      }
    }
    tx.setMarker(key, nowMs);
    return "applied";
  });
}

async function refundEventFee(
  deps: RefundEffectsDeps,
  payment: PaymentDoc,
  refundId: string,
  _refundMinor: number,
  full: boolean,
  nowMs: number,
): Promise<RefundEffectOutcome> {
  const key = `refunded:${refundId}`;
  const done = await deps.runner.run((tx) => tx.hasMarker(key));
  if (done) return "already_applied";
  if (full) {
    try {
      await deps.events.cancelRegistration({
        registrationId: payment.refId,
        actorUserId: "system",
        actorIsStaff: true,
        nowMs,
        reservationMinutes: deps.reservationMinutes,
      });
    } catch (e) {
      // Kayıt yok ya da zaten iptal/geçersiz durumda: iade yine de geçerlidir.
      if (!(e instanceof DomainError)) throw e;
    }
  }
  await deps.runner.run(async (tx) => {
    if (!(await tx.hasMarker(key))) tx.setMarker(key, nowMs);
  });
  return "applied";
}

/** Taramanın kaynağı: son dönemde başarılı iadeler (etkisi uygulanmamış olabilir). */
export interface RefundSweepRow {
  readonly refundId: string;
  readonly payment: PaymentDoc;
  readonly refundMinor: number;
  /** Bu iade ile ödemenin TAMAMI iade edilmiş oldu mu (önceki iadeler dahil kümülatif)? */
  readonly full: boolean;
}

export interface RefundSweepSource {
  listSucceededSince(sinceMs: number, limit: number): Promise<readonly RefundSweepRow[]>;
}

export interface RefundSweepReport {
  readonly checked: number;
  readonly applied: number;
  readonly errors: number;
}

/**
 * Zamanlanmış tarama: `effectsApplied:false` dönen veya yarıda kalan iadelerin etkilerini yeniden
 * uygular. İşaretçi sayesinde zaten uygulananlar `already_applied` olur (çift düşme yok).
 */
export async function sweepRefundEffects(
  source: RefundSweepSource,
  deps: RefundEffectsDeps,
  sinceMs: number,
  limit: number,
): Promise<RefundSweepReport> {
  const rows = await source.listSucceededSince(sinceMs, limit);
  let applied = 0;
  let errors = 0;
  for (const r of rows) {
    try {
      if ((await applyRefundEffects(deps, r.payment, r.refundId, r.refundMinor, r.full)) === "applied") applied++;
    } catch {
      errors++; // bir iade takılırsa diğerleri işlenmeye devam eder
    }
  }
  return { checked: rows.length, applied, errors };
}
