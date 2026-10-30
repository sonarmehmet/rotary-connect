import { DueDoc, DueStatus, applyPayment, deriveDueStatus } from "../dues/dues";
import { EventRegistrationService } from "../events/service";
import { DomainError } from "../lib/errors";
import {
  NotificationType,
  NotificationWriter,
  buildNotification,
} from "../notifications/notifications";
import { PaymentDoc } from "./repo";
import { Effect } from "./webhook";

/**
 * Ödeme sonucunun iş kayıtlarına yansıması (borç, bağış, kampanya toplamı, etkinlik kaydı,
 * bildirim). Webhook/mutabakat/manuel kayıt aynı yolu kullanır ve HER ADIM İDEMPOTENTTİR:
 * işlem tekrarlanırsa (yeniden deneme, çift webhook) ikinci kez uygulanmaz.
 *
 * Çağıran taraf hata alırsa işlemi yeniden denemelidir (ör. Cloud Tasks); ödeme kaydı zaten
 * `succeeded` olduğundan etkiler ayrı bir adımdır ve güvenle tekrarlanır.
 */
export interface DueEntry extends DueDoc {
  readonly id: string;
  readonly userId: string;
  readonly currency: string;
}

export interface DuePaymentRecord {
  readonly dueId: string;
  readonly paymentId: string;
  readonly userId: string;
  readonly amountMinor: number;
  readonly currency: string;
  readonly source: "online" | "manual";
  readonly createdAtMs: number;
}

/** Firestore kuralı: tüm okumalar (get*, has*) yazmalardan (set*, update*, create*) ÖNCE yapılır. */
export interface EffectsTx {
  hasMarker(key: string): Promise<boolean>;
  getDue(id: string): Promise<DueEntry | null>;
  getDonationByPayment(paymentId: string): Promise<{ id: string; status: string } | null>;
  getCampaign(id: string): Promise<{ verifiedTotalMinor: number; donorCount: number } | null>;
  setMarker(key: string, nowMs: number): void;
  updateDue(id: string, patch: { paidMinor: number; status: DueStatus }): void;
  createDuePayment(r: DuePaymentRecord): void;
  updateDonation(id: string, patch: { status: "succeeded" | "failed" | "refunded" | "partially_refunded" }): void;
  updateCampaign(id: string, patch: { verifiedTotalMinor: number; donorCount: number }): void;
}

export interface EffectsTxRunner {
  run<T>(fn: (tx: EffectsTx) => Promise<T>): Promise<T>;
}

export interface RefundRequestSink {
  /** `paymentId` ile İDEMPOTENT olmalı (aynı ödeme için tekrar çağrı ikinci talep açmaz). */
  request(payment: PaymentDoc, reason: string): Promise<void>;
}

export interface EffectsDeps {
  readonly runner: EffectsTxRunner;
  readonly events: EventRegistrationService;
  readonly notifications: NotificationWriter;
  readonly refunds: RefundRequestSink;
  readonly nowMs: () => number;
}

export type EffectOutcome =
  | { readonly result: "applied" | "already_applied" }
  | { readonly result: "refund_required"; readonly reason: string };

const NOTIFY: Record<PaymentDoc["kind"], NotificationType> = {
  membership_due: "due_paid",
  donation: "donation_confirmed",
  event_fee: "registration_confirmed",
};

async function notify(deps: EffectsDeps, p: PaymentDoc, type: NotificationType, nowMs: number): Promise<void> {
  if (p.userId === null) return; // misafir bağışçıya bildirim yok
  await deps.notifications.createIfAbsent([
    { id: `pay_${p.id}_${type}`, doc: buildNotification(type, p.userId, p.id, nowMs) },
  ]);
}

async function collectDue(deps: EffectsDeps, p: PaymentDoc, nowMs: number): Promise<EffectOutcome> {
  return deps.runner.run(async (tx): Promise<EffectOutcome> => {
    const key = `collected:${p.id}`;
    if (await tx.hasMarker(key)) return { result: "already_applied" };
    const due = await tx.getDue(p.refId);
    if (!due) return { result: "refund_required", reason: "due_not_found" };
    if (due.currency !== p.currency) return { result: "refund_required", reason: "currency_mismatch" };
    const status = deriveDueStatus(due, nowMs);
    if (status === "cancelled" || status === "refunded") {
      return { result: "refund_required", reason: "due_not_payable" };
    }
    if (due.paidMinor + p.amountMinor > due.amountMinor) {
      return { result: "refund_required", reason: "overpayment" };
    }
    const next = applyPayment(due, p.amountMinor);
    tx.updateDue(due.id, { paidMinor: next.paidMinor, status: deriveDueStatus(next, nowMs) });
    tx.createDuePayment({
      dueId: due.id,
      paymentId: p.id,
      userId: p.userId ?? due.userId,
      amountMinor: p.amountMinor,
      currency: p.currency,
      source: p.manual ? "manual" : "online",
      createdAtMs: nowMs,
    });
    tx.setMarker(key, nowMs);
    return { result: "applied" };
  });
}

async function collectDonation(deps: EffectsDeps, p: PaymentDoc, nowMs: number): Promise<EffectOutcome> {
  return deps.runner.run(async (tx): Promise<EffectOutcome> => {
    const key = `collected:${p.id}`;
    if (await tx.hasMarker(key)) return { result: "already_applied" };
    const donation = await tx.getDonationByPayment(p.id);
    const campaign = p.refId === "general" ? null : await tx.getCampaign(p.refId);
    if (donation) tx.updateDonation(donation.id, { status: "succeeded" });
    // Simülasyon ödemeleri doğrulanmış toplama ASLA girmez (proje kuralı).
    if (campaign && !p.simulated) {
      tx.updateCampaign(p.refId, {
        verifiedTotalMinor: campaign.verifiedTotalMinor + p.amountMinor,
        donorCount: campaign.donorCount + 1,
      });
    }
    tx.setMarker(key, nowMs);
    return { result: "applied" };
  });
}

async function collectEventFee(deps: EffectsDeps, p: PaymentDoc, nowMs: number): Promise<EffectOutcome> {
  try {
    const r = await deps.events.confirmPaid(p.refId, p.id, nowMs);
    if (r.outcome === "refund_required") {
      return { result: "refund_required", reason: "registration_not_confirmable" };
    }
    return { result: r.outcome === "confirmed" ? "applied" : "already_applied" };
  } catch (e) {
    if (e instanceof DomainError && e.code === "not-found") {
      return { result: "refund_required", reason: "registration_not_found" };
    }
    throw e;
  }
}

/** Tahsil edilmiş ödemenin etkilerini uygular. Para alınmış ama kayıt kesinleşemiyorsa iade talebi açar. */
export async function applyCollected(deps: EffectsDeps, p: PaymentDoc): Promise<EffectOutcome> {
  const nowMs = deps.nowMs();
  const outcome =
    p.kind === "membership_due"
      ? await collectDue(deps, p, nowMs)
      : p.kind === "donation"
        ? await collectDonation(deps, p, nowMs)
        : await collectEventFee(deps, p, nowMs);
  if (outcome.result === "refund_required") {
    await deps.refunds.request(p, outcome.reason);
    return outcome;
  }
  await notify(deps, p, NOTIFY[p.kind], nowMs); // idempotent kimlik: tekrar çağrı çift bildirim üretmez
  return outcome;
}

/**
 * Başarısız/iptal ödeme: bağış kaydı `failed` olur. Etkinlik rezervasyonu BİLEREK serbest
 * bırakılmaz: kullanıcı süre dolmadan yeniden ödemeyi deneyebilir, süre dolunca zaten düşer.
 */
export async function applyFailed(deps: EffectsDeps, p: PaymentDoc): Promise<EffectOutcome> {
  const nowMs = deps.nowMs();
  const outcome = await deps.runner.run(async (tx): Promise<EffectOutcome> => {
    const key = `failed:${p.id}`;
    if (await tx.hasMarker(key)) return { result: "already_applied" };
    const donation = p.kind === "donation" ? await tx.getDonationByPayment(p.id) : null;
    if (donation) tx.updateDonation(donation.id, { status: "failed" });
    tx.setMarker(key, nowMs);
    return { result: "applied" };
  });
  await notify(deps, p, "payment_result", nowMs);
  return outcome;
}

/** `processWebhook` / mutabakat sonucundaki etkileri sırayla uygular. */
export async function applyEffects(deps: EffectsDeps, effects: readonly Effect[]): Promise<EffectOutcome[]> {
  const out: EffectOutcome[] = [];
  for (const e of effects) {
    out.push(e.type === "collected" ? await applyCollected(deps, e.payment) : await applyFailed(deps, e.payment));
  }
  return out;
}
