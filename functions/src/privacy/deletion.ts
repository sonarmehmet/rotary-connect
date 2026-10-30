/**
 * KVKK hesap silme planı. Finansal kayıtlar yasal saklama yükümlülüğü nedeniyle SİLİNMEZ,
 * kişi ile bağı kesilerek anonimleştirilir. Hukuki saklama süreleri için hukuk/mali müşavir
 * onayı gerekir; süre burada ayardan gelir, sabit kodlanmaz.
 */
export interface DeletionInput {
  readonly userId: string;
  readonly hasPendingPayments: boolean;
  readonly hasOutstandingDues: boolean;
  readonly hasFutureEventRegistrations: boolean;
}

export type DeletionBlocker = "pending_payments" | "outstanding_dues" | "future_event_registrations";

export interface DeletionPlan {
  readonly canProceed: boolean;
  readonly blockers: DeletionBlocker[];
  /** Silinecek koleksiyon/alanlar. */
  readonly delete: readonly string[];
  /** Kimliksizleştirilecek (userId/ad/e-posta alanları temizlenir) ancak saklanacak kayıtlar. */
  readonly anonymize: readonly string[];
}

export function planAccountDeletion(i: DeletionInput): DeletionPlan {
  const blockers: DeletionBlocker[] = [];
  if (i.hasPendingPayments) blockers.push("pending_payments");
  if (i.hasOutstandingDues) blockers.push("outstanding_dues");
  if (i.hasFutureEventRegistrations) blockers.push("future_event_registrations");
  return {
    canProceed: blockers.length === 0,
    blockers,
    delete: ["users/{uid}", "notifications (kullanıcıya ait)", "users/{uid}.fcmTokens", "auth hesabı"],
    anonymize: [
      "payments (userId, donor bilgisi)",
      "donations (userId, donor)",
      "membership_dues / membership_due_payments (userId)",
      "event_registrations (userId, participant)",
      "club_members (userId, memberNo korunur)",
    ],
  };
}

const ANON = "silinmiş-kullanıcı";

/** Bir kayıttaki kişisel alanları temizler; tutar/tarih/durum gibi finansal alanlar korunur. */
export function anonymizeRecord<T extends Record<string, unknown>>(rec: T): T {
  const out: Record<string, unknown> = { ...rec };
  for (const k of ["userId"]) if (k in out) out[k] = ANON;
  for (const k of ["donor", "participant"]) if (k in out) out[k] = { name: ANON, anonymous: true };
  for (const k of ["email", "phone", "displayName", "name"]) if (k in out) delete out[k];
  return out as T;
}
