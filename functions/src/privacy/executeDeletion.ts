import { ANON } from "./deletion";
import { DeletionBlocker, planAccountDeletion } from "./deletion";

/**
 * KVKK silme yürütücüsü. Talep onaylandıktan sonra (arka plan işi) çalışır. Her adım tekrar
 * çalıştırılabilir (yarıda kalırsa kaldığı yerden sürer). Mali kayıtlar silinmez, kişiden koparılır.
 * Hesap (Auth) EN SON silinir: önceki adımlar başarısız olursa kullanıcı hesabına erişimi kaybetmez.
 */
export interface PersonalDataStore {
  /** `userId` alanı eşleşen kayıtlara `patch`'i uygular; etkilenen kayıt sayısını döner. */
  anonymize(collection: string, userId: string, patch: Record<string, unknown>): Promise<number>;
  deleteWhereUser(collection: string, userId: string): Promise<number>;
  deleteUserDoc(userId: string): Promise<void>;
}

export interface AuthAdmin {
  /** Hesap zaten yoksa hata vermemeli (idempotent). */
  deleteUser(userId: string): Promise<void>;
}

export interface DeletionFactsReader {
  hasPendingPayments(userId: string): Promise<boolean>;
  hasOutstandingDues(userId: string): Promise<boolean>;
  hasFutureEventRegistrations(userId: string): Promise<boolean>;
}

const PERSON = { name: ANON, anonymous: true } as const;

/** Koleksiyon → anonimleştirme yaması (tutar, tarih, durum gibi mali alanlar korunur). */
export const ANONYMIZE_PATCHES: Readonly<Record<string, Record<string, unknown>>> = {
  payments: { userId: ANON },
  donations: { userId: ANON, donor: PERSON },
  membership_dues: { userId: ANON },
  membership_due_payments: { userId: ANON },
  event_registrations: { userId: ANON, participant: PERSON },
  club_members: { userId: ANON },
};

export type DeletionResult =
  | { readonly done: true; readonly anonymized: number; readonly deleted: number }
  | { readonly done: false; readonly blockers: DeletionBlocker[] };

export async function executeAccountDeletion(
  deps: { store: PersonalDataStore; auth: AuthAdmin; facts: DeletionFactsReader },
  userId: string,
): Promise<DeletionResult> {
  // Onay ile yürütme arasında durum değişmiş olabilir (yeni borç/ödeme): yeniden denetle.
  const plan = planAccountDeletion({
    userId,
    hasPendingPayments: await deps.facts.hasPendingPayments(userId),
    hasOutstandingDues: await deps.facts.hasOutstandingDues(userId),
    hasFutureEventRegistrations: await deps.facts.hasFutureEventRegistrations(userId),
  });
  if (!plan.canProceed) return { done: false, blockers: plan.blockers };

  let anonymized = 0;
  for (const [col, patch] of Object.entries(ANONYMIZE_PATCHES)) {
    anonymized += await deps.store.anonymize(col, userId, patch);
  }
  const deleted = await deps.store.deleteWhereUser("notifications", userId);
  await deps.store.deleteUserDoc(userId);
  await deps.auth.deleteUser(userId);
  return { done: true, anonymized, deleted };
}
