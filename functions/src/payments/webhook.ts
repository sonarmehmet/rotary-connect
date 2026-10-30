import { DomainError } from "../lib/errors";
import { PaymentStatus, decideWebhook } from "./paymentState";
import { PaymentDoc, PaymentTxRunner } from "./repo";

export interface ProviderEvent {
  readonly providerRef: string;
  readonly status: PaymentStatus;
  /** Sağlayıcının bildirdiği tutar; başarılı bildirimde sunucudaki beklenen tutarla BİREBİR eşleşmeli. */
  readonly amountMinor: number | null;
  readonly currency: string | null;
  readonly failureCode?: string;
}

/** Başarılı olduğunda hedef kaydın (aidat/bağış/etkinlik) güncellenmesi için idempotent yan etki. */
export type Effect =
  | { type: "collected"; payment: PaymentDoc }
  | { type: "failed"; payment: PaymentDoc };

export type WebhookOutcome =
  | { result: "applied"; payment: PaymentDoc; effects: Effect[] }
  | { result: "ignored"; reason: "duplicate" | "invalid_transition" | "unknown_payment" }
  | { result: "flagged"; reason: "amount_mismatch"; payment: PaymentDoc };

export interface WebhookInput {
  readonly event: ProviderEvent;
  /** İmza doğrulaması çağıran tarafta (sağlayıcıya özgü HMAC) yapılır; sonucu buraya verilir. */
  readonly signatureValid: boolean;
  readonly nowMs: number;
}

/**
 * Sağlayıcı bildirimini işler. İlkeler:
 * - İmza geçersizse HİÇBİR şey okunmaz/yazılmaz (permission-denied).
 * - Aynı bildirim tekrar gelirse etkisizdir (idempotent); sıra bozukluğu geri adım attırmaz.
 * - Tutar/para birimi uyuşmazlığı olan "başarılı" bildirim tahsilat SAYILMAZ, işaretlenir.
 * - Bilinmeyen providerRef yok sayılır (sağlayıcı tekrar denemesin diye çağıran 200 döner).
 */
export async function processWebhook(
  runner: PaymentTxRunner,
  input: WebhookInput,
): Promise<WebhookOutcome> {
  if (!input.signatureValid) {
    throw new DomainError("permission-denied", "Geçersiz bildirim imzası", "bad_signature");
  }
  const ev = input.event;

  return runner.run(async (tx): Promise<WebhookOutcome> => {
    const payment = await tx.findByProviderRef(ev.providerRef);
    if (!payment) return { result: "ignored", reason: "unknown_payment" };

    if (ev.status === "succeeded") {
      const mismatch = ev.amountMinor !== payment.amountMinor || ev.currency !== payment.currency;
      if (mismatch && payment.status === "pending") {
        await tx.updatePayment(payment.id, { flag: "amount_mismatch", updatedAtMs: input.nowMs });
        return { result: "flagged", reason: "amount_mismatch", payment: { ...payment, flag: "amount_mismatch" } };
      }
    }

    const decision = decideWebhook(payment.status, ev.status);
    if (decision.action === "ignore") return { result: "ignored", reason: decision.reason };

    const patch = {
      status: decision.next,
      updatedAtMs: input.nowMs,
      succeededAtMs: decision.next === "succeeded" ? input.nowMs : payment.succeededAtMs,
      failureCode: decision.next === "failed" ? (ev.failureCode ?? "unknown") : payment.failureCode,
    } as const;
    await tx.updatePayment(payment.id, patch);
    const updated: PaymentDoc = { ...payment, ...patch };

    const effects: Effect[] = [];
    if (decision.next === "succeeded") effects.push({ type: "collected", payment: updated });
    if (decision.next === "failed" || decision.next === "cancelled") {
      effects.push({ type: "failed", payment: updated });
    }
    return { result: "applied", payment: updated, effects };
  });
}
