import { DomainError } from "../lib/errors";
import { Money, assertValidMoney } from "../lib/money";
import { PaymentProvider } from "./provider";
import { PaymentKindWire, PaymentDoc, PaymentTxRunner } from "./repo";

export interface StartPaymentInput {
  readonly kind: PaymentKindWire;
  readonly refId: string;
  readonly userId: string | null;
  /** Tutar SUNUCUDA çözülmüş olmalı (amounts.ts / dues.ts); istemciden gelen ham değer değil. */
  readonly amount: Money;
  /** İstemcinin ürettiği tekrar-deneme anahtarı: aynı anahtar = aynı ödeme. */
  readonly clientKey: string;
  readonly description: string;
  readonly nowMs: number;
  readonly mode: "simulation" | "live";
  /** Kimlik üretici (testte deterministik). */
  readonly newId: () => string;
}

export interface StartPaymentResult {
  readonly payment: PaymentDoc;
  readonly checkoutUrl: string | null;
  readonly reused: boolean;
}

export function idempotencyKeyFor(i: Pick<StartPaymentInput, "kind" | "refId" | "userId" | "clientKey">): string {
  return `${i.kind}:${i.refId}:${i.userId ?? "guest"}:${i.clientKey}`;
}

/**
 * Ödeme kaydı + sağlayıcı oturumu açar. Aynı idempotency anahtarıyla tekrar çağrılırsa
 * YENİ ödeme oluşturmaz, mevcut kaydı döner (çift tıklama / ağ yeniden denemesi güvenli).
 * Canlı modda simüle edilmiş sağlayıcı kullanılamaz (yanlışlıkla sahte tahsilatı önler).
 */
export async function startPayment(
  runner: PaymentTxRunner,
  provider: PaymentProvider,
  input: StartPaymentInput,
): Promise<StartPaymentResult> {
  assertValidMoney(input.amount);
  if (input.clientKey.trim().length < 8) {
    throw new DomainError("invalid-argument", "İşlem anahtarı geçersiz", "bad_client_key");
  }
  const key = idempotencyKeyFor(input);

  // 1) Kaydı (veya mevcut kaydı) transaction içinde oluştur.
  const { payment, reused } = await runner.run(async (tx) => {
    const existing = await tx.findByIdempotencyKey(key);
    if (existing) return { payment: existing, reused: true };
    const created = await tx.createPayment({
      kind: input.kind,
      refId: input.refId,
      userId: input.userId,
      amountMinor: input.amount.amountMinor,
      currency: input.amount.currency,
      status: "created",
      provider: provider.name,
      providerRef: null,
      simulated: false,
      idempotencyKey: key,
      manual: false,
      refundedMinor: 0,
      createdAtMs: input.nowMs,
      updatedAtMs: input.nowMs,
      succeededAtMs: null,
      failureCode: null,
      flag: null,
    });
    return { payment: created, reused: false };
  });

  if (reused) {
    if (payment.amountMinor !== input.amount.amountMinor || payment.currency !== input.amount.currency) {
      throw new DomainError("already-exists", "Bu anahtar farklı bir tutarla kullanılmış", "key_amount_mismatch");
    }
    return { payment, checkoutUrl: null, reused: true };
  }

  // 2) Sağlayıcı oturumu (dış çağrı transaction DIŞINDA).
  const session = await provider.createSession({
    paymentId: payment.id,
    amount: input.amount,
    description: input.description,
  });
  if (input.mode === "live" && session.simulated) {
    await runner.run((tx) =>
      tx.updatePayment(payment.id, { status: "failed", failureCode: "simulated_in_live", updatedAtMs: input.nowMs }),
    );
    throw new DomainError("failed-precondition", "Canlı modda simülasyon sağlayıcısı kullanılamaz", "simulated_in_live");
  }

  // 3) created → pending, sağlayıcı referansını yaz.
  await runner.run((tx) =>
    tx.updatePayment(payment.id, {
      status: "pending",
      providerRef: session.providerRef,
      simulated: session.simulated,
      updatedAtMs: input.nowMs,
    }),
  );
  return {
    payment: { ...payment, status: "pending", providerRef: session.providerRef, simulated: session.simulated },
    checkoutUrl: session.checkoutUrl,
    reused: false,
  };
}
