import { PaymentStatus } from "./paymentState";

export type PaymentKindWire = "membership_due" | "donation" | "event_fee";

export interface PaymentDoc {
  readonly id: string;
  readonly kind: PaymentKindWire;
  readonly refId: string;
  readonly userId: string | null;
  readonly amountMinor: number;
  readonly currency: string;
  readonly status: PaymentStatus;
  readonly provider: string;
  readonly providerRef: string | null;
  readonly simulated: boolean;
  readonly idempotencyKey: string;
  readonly manual: boolean;
  readonly refundedMinor: number;
  readonly createdAtMs: number;
  readonly updatedAtMs: number;
  readonly succeededAtMs: number | null;
  readonly failureCode: string | null;
  /** Şüpheli durum (ör. tutar uyuşmazlığı): insan incelemesi gerekir, tahsilat sayılmaz. */
  readonly flag: string | null;
}

/** Transaction içinde kullanılan ödeme erişimi (Firestore adaptörü bunu uygular). */
export interface PaymentTx {
  getPayment(id: string): Promise<PaymentDoc | null>;
  findByIdempotencyKey(key: string): Promise<PaymentDoc | null>;
  findByProviderRef(ref: string): Promise<PaymentDoc | null>;
  /** Belirtilen zamandan önce oluşturulmuş ve hâlâ `pending` olan ödemeler (mutabakat için). */
  listPendingCreatedBefore(beforeMs: number, limit: number): Promise<PaymentDoc[]>;
  createPayment(doc: Omit<PaymentDoc, "id">): Promise<PaymentDoc>;
  updatePayment(id: string, patch: Partial<Omit<PaymentDoc, "id">>): Promise<void>;
}

export interface PaymentTxRunner {
  run<T>(fn: (tx: PaymentTx) => Promise<T>): Promise<T>;
}
