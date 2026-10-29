/** packages/shared/lib/src/payment_status.dart ile BİREBİR aynı durum makinesi. */
export const PAYMENT_STATUSES = [
  "created",
  "pending",
  "succeeded",
  "failed",
  "cancelled",
  "refunded",
  "partially_refunded",
] as const;

export type PaymentStatus = (typeof PAYMENT_STATUSES)[number];

const ALLOWED_NEXT: Record<PaymentStatus, readonly PaymentStatus[]> = {
  created: ["pending", "failed", "cancelled"],
  pending: ["succeeded", "failed", "cancelled"],
  succeeded: ["refunded", "partially_refunded"],
  partially_refunded: ["refunded", "partially_refunded"],
  failed: [],
  cancelled: [],
  refunded: [],
};

export function canTransition(from: PaymentStatus, to: PaymentStatus): boolean {
  return ALLOWED_NEXT[from].includes(to);
}

export type WebhookDecision =
  | { action: "apply"; next: PaymentStatus }
  | { action: "ignore"; reason: "duplicate" | "invalid_transition" };

/**
 * Webhook idempotency: aynı bildirim tekrar gelirse (mevcut durum == gelen durum)
 * hiçbir şey yapılmaz; geçersiz geçişler (ör. failed → succeeded) yok sayılır.
 * Bu karar Firestore transaction'ı içinde, ödeme belgesi okunduktan sonra verilmelidir.
 */
export function decideWebhook(
  current: PaymentStatus,
  incoming: PaymentStatus,
): WebhookDecision {
  if (current === incoming) return { action: "ignore", reason: "duplicate" };
  if (!canTransition(current, incoming)) {
    return { action: "ignore", reason: "invalid_transition" };
  }
  return { action: "apply", next: incoming };
}

/** Yalnızca doğrulanmış tahsilatlar toplamlara girer. */
export function countsAsCollected(status: PaymentStatus): boolean {
  return status === "succeeded" || status === "partially_refunded";
}
