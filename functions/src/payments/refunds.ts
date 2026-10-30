import { DomainError } from "../lib/errors";
import { PaymentStatus } from "./paymentState";

export interface RefundablePayment {
  readonly status: PaymentStatus;
  readonly amountMinor: number;
  readonly refundedMinor: number;
  readonly simulated: boolean;
}

export interface RefundPlan {
  readonly refundMinor: number;
  readonly newRefundedMinor: number;
  readonly nextStatus: Extract<PaymentStatus, "refunded" | "partially_refunded">;
}

/**
 * İade planı: yalnızca tahsil edilmiş ödemeler, toplam iade ≤ orijinal tutar.
 * `refundMinor` verilmezse kalan tutarın tamamı iade edilir.
 */
export function planRefund(p: RefundablePayment, refundMinor?: number): RefundPlan {
  if (p.status !== "succeeded" && p.status !== "partially_refunded") {
    throw new DomainError("failed-precondition", "Bu ödeme iade edilemez", "not_refundable");
  }
  const remaining = p.amountMinor - p.refundedMinor;
  const amount = refundMinor ?? remaining;
  if (!Number.isSafeInteger(amount) || amount <= 0) {
    throw new DomainError("invalid-argument", "İade tutarı geçersiz", "invalid_amount");
  }
  if (amount > remaining) {
    throw new DomainError("invalid-argument", "İade tutarı kalan tutarı aşıyor", "exceeds_remaining");
  }
  const newRefundedMinor = p.refundedMinor + amount;
  return {
    refundMinor: amount,
    newRefundedMinor,
    nextStatus: newRefundedMinor === p.amountMinor ? "refunded" : "partially_refunded",
  };
}
