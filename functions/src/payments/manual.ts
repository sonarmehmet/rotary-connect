import { DomainError } from "../lib/errors";
import { Role, requireRole } from "../lib/roles";
import { assertValidMoney } from "../lib/money";
import { PaymentDoc, PaymentTxRunner } from "./repo";

export interface ManualPaymentInput {
  readonly actorRole: unknown;
  readonly actorId: string;
  readonly kind: "membership_due" | "donation" | "event_fee";
  readonly refId: string;
  readonly amountMinor: number;
  readonly currency: string;
  readonly receivedAtMs: number;
  readonly note: string;
  readonly nowMs: number;
  /** Ödemenin ait olduğu üye/kullanıcı (kullanıcı kendi ödemesini görebilsin diye). */
  readonly userId?: string | null;
}

export interface ManualPaymentRecord {
  readonly kind: ManualPaymentInput["kind"];
  readonly refId: string;
  readonly amountMinor: number;
  readonly currency: string;
  readonly status: "succeeded";
  readonly provider: "manual";
  readonly manual: true;
  readonly simulated: false;
  readonly recordedBy: string;
  readonly note: string;
  readonly createdAtMs: number;
  readonly succeededAtMs: number;
  readonly idempotencyKey: string;
}

const ALLOWED_ROLES: readonly Role[] = ["finance_manager"];

/**
 * Manuel (elden/havale) ödeme kaydı. Yalnızca finans yöneticisi; açıklama zorunlu;
 * tarih gelecekte olamaz. Çevrim içi ödemelerden `manual: true` ile ayrılır ve denetlenebilir.
 */
export function buildManualPayment(i: ManualPaymentInput): ManualPaymentRecord {
  requireRole(i.actorRole, ALLOWED_ROLES);
  assertValidMoney({ amountMinor: i.amountMinor, currency: i.currency });
  const note = i.note.trim();
  if (note.length < 5) {
    throw new DomainError("invalid-argument", "Açıklama en az 5 karakter olmalı", "note_required");
  }
  if (i.receivedAtMs > i.nowMs) {
    throw new DomainError("invalid-argument", "Ödeme tarihi gelecekte olamaz", "future_date");
  }
  return {
    kind: i.kind,
    refId: i.refId,
    amountMinor: i.amountMinor,
    currency: i.currency,
    status: "succeeded",
    provider: "manual",
    manual: true,
    simulated: false,
    recordedBy: i.actorId,
    note,
    createdAtMs: i.nowMs,
    succeededAtMs: i.receivedAtMs,
    // Aynı ödeme iki kez girilemesin: borç/kayıt + tutar + gün
    idempotencyKey: `manual:${i.kind}:${i.refId}:${i.amountMinor}:${Math.floor(i.receivedAtMs / 86_400_000)}`,
  };
}

/**
 * Manuel ödemeyi kalıcılaştırır. Aynı (tür, kayıt, tutar, gün) ikinci kez girilemez.
 * Not: hedef borcun/bağışın/kaydın güncellenmesi çağıran orkestrasyonun işidir.
 */
export async function recordManualPayment(
  runner: PaymentTxRunner,
  input: ManualPaymentInput,
): Promise<PaymentDoc> {
  const rec = buildManualPayment(input);
  return runner.run(async (tx) => {
    const dup = await tx.findByIdempotencyKey(rec.idempotencyKey);
    if (dup) {
      throw new DomainError("already-exists", "Bu manuel ödeme zaten kaydedilmiş", "duplicate_manual_payment");
    }
    return tx.createPayment({
      kind: rec.kind,
      refId: rec.refId,
      userId: input.userId ?? null,
      amountMinor: rec.amountMinor,
      currency: rec.currency,
      status: "succeeded",
      provider: "manual",
      providerRef: null,
      simulated: false,
      idempotencyKey: rec.idempotencyKey,
      manual: true,
      recordedBy: rec.recordedBy,
      note: rec.note,
      refundedMinor: 0,
      createdAtMs: rec.createdAtMs,
      updatedAtMs: rec.createdAtMs,
      succeededAtMs: rec.succeededAtMs,
      failureCode: null,
      flag: null,
    });
  });
}
