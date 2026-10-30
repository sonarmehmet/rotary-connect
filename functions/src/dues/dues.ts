/** Aidat kuralları (saf fonksiyonlar). Tutar ve dönemler kodda sabit değil, panelden gelir. */
export type DueStatus =
  | "unpaid"
  | "partially_paid"
  | "paid"
  | "overdue"
  | "cancelled"
  | "refunded";

export interface DueDoc {
  readonly amountMinor: number;
  readonly paidMinor: number;
  readonly dueDateMs: number;
  readonly cancelled: boolean;
  readonly refunded: boolean;
  readonly allowPartial: boolean;
}

export function remainingMinor(d: DueDoc): number {
  return Math.max(0, d.amountMinor - d.paidMinor);
}

/** Durum tek yerden, borç alanlarından türetilir (elle durum yazılmaz). */
export function deriveDueStatus(d: DueDoc, nowMs: number): DueStatus {
  if (d.cancelled) return "cancelled";
  if (d.refunded) return "refunded";
  if (d.paidMinor >= d.amountMinor) return "paid";
  if (nowMs > d.dueDateMs) return "overdue";
  return d.paidMinor > 0 ? "partially_paid" : "unpaid";
}

export type PayableDecision =
  | { ok: true; amountMinor: number }
  | {
      ok: false;
      reason: "not_payable" | "partial_not_allowed" | "exceeds_remaining" | "invalid_amount";
    };

/**
 * Üyenin ödemek istediği tutarı doğrular. `requestedMinor` verilmezse kalan tutarın tamamı.
 * Kısmi ödeme yalnızca borçta `allowPartial` ve kulüp ayarı açıksa mümkündür.
 */
export function resolveDuePayment(
  d: DueDoc,
  nowMs: number,
  requestedMinor: number | undefined,
  partialEnabledBySettings: boolean,
): PayableDecision {
  const status = deriveDueStatus(d, nowMs);
  if (status === "cancelled" || status === "refunded" || status === "paid") {
    return { ok: false, reason: "not_payable" };
  }
  const remaining = remainingMinor(d);
  if (requestedMinor === undefined || requestedMinor === remaining) {
    return { ok: true, amountMinor: remaining };
  }
  if (!Number.isSafeInteger(requestedMinor) || requestedMinor <= 0) {
    return { ok: false, reason: "invalid_amount" };
  }
  if (requestedMinor > remaining) return { ok: false, reason: "exceeds_remaining" };
  if (!d.allowPartial || !partialEnabledBySettings) {
    return { ok: false, reason: "partial_not_allowed" };
  }
  return { ok: true, amountMinor: requestedMinor };
}

/** Başarılı ödeme sonrası yeni ödenen toplam. Aşırı ödeme engellenir. */
export function applyPayment(d: DueDoc, paymentMinor: number): DueDoc {
  if (!Number.isSafeInteger(paymentMinor) || paymentMinor <= 0) {
    throw new Error("Ödeme tutarı geçersiz");
  }
  if (d.paidMinor + paymentMinor > d.amountMinor) {
    throw new Error("Ödeme borcu aşıyor");
  }
  return { ...d, paidMinor: d.paidMinor + paymentMinor };
}
