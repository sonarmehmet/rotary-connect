import { buildAuditEntry } from "../audit/audit";
import { DomainError } from "../lib/errors";
import { DeletionBlocker, DeletionPlan, planAccountDeletion } from "../privacy/deletion";
import { constantTimeEqual } from "../lib/safeEqual";
import { AuditSink, CallableAuth, requireAuth } from "./handlers";
import { asEmail, asObject, asString } from "./validate";

// ------------------------------------------------------------ bağış makbuzu

export interface ReceiptRow {
  readonly id: string;
  readonly paymentId: string;
  readonly userId: string | null;
  readonly donorEmail: string | null;
  readonly donorName: string;
  readonly anonymous: boolean;
  readonly amountMinor: number;
  readonly currency: string;
  readonly status: string;
  readonly receiptNo: string | null;
  readonly campaignId: string | null;
  readonly simulated: boolean;
  readonly createdAtMs: number;
}

export interface ReceiptReader {
  getByDonationId(id: string): Promise<ReceiptRow | null>;
}

export interface Receipt {
  readonly receiptNo: string;
  readonly donationId: string;
  readonly donorName: string;
  readonly amountMinor: number;
  readonly currency: string;
  readonly campaignId: string | null;
  readonly createdAtMs: number;
  /** Simülasyon bağışı resmî makbuz DEĞİLDİR; arayüz bunu açıkça göstermelidir. */
  readonly simulated: boolean;
}

/**
 * Makbuz: giriş yapmış sahibi veya misafir (bağış no + bağışta kullandığı e-posta) alabilir.
 * Sahip olmayan ve e-postası eşleşmeyen herkes, bağışın var olup olmadığını öğrenemesin diye
 * aynı "not-found" hatasını alır. Yalnızca başarılı (ve iade edilmemiş) bağışa makbuz verilir.
 */
export async function getDonationReceiptHandler(
  deps: { readonly receipts: ReceiptReader },
  auth: CallableAuth | null | undefined,
  data: unknown,
): Promise<Receipt> {
  const o = asObject(data, "data");
  const donationId = asString(o["donationId"], "donationId", { max: 100 });
  const uid = auth ? requireAuth(auth).uid : null;
  const email = uid === null ? asEmail(o["email"]) : null;

  const row = await deps.receipts.getByDonationId(donationId);
  const owner = row !== null && uid !== null && row.userId === uid;
  const guestOk =
    row !== null && uid === null && row.userId === null && row.donorEmail !== null &&
    email !== null && constantTimeEqual(row.donorEmail.toLowerCase(), email.toLowerCase());
  if (!row || !(owner || guestOk)) {
    throw new DomainError("not-found", "Bağış bulunamadı", "donation_not_found");
  }
  if (row.status !== "succeeded" || row.receiptNo === null) {
    throw new DomainError("failed-precondition", "Bu bağış için makbuz henüz düzenlenmedi", "receipt_unavailable");
  }
  return {
    receiptNo: row.receiptNo,
    donationId: row.id,
    donorName: row.anonymous ? "Anonim bağışçı" : row.donorName,
    amountMinor: row.amountMinor,
    currency: row.currency,
    campaignId: row.campaignId,
    createdAtMs: row.createdAtMs,
    simulated: row.simulated,
  };
}

// ------------------------------------------------------------ KVKK silme talebi

export interface DeletionFacts {
  hasPendingPayments(userId: string): Promise<boolean>;
  hasOutstandingDues(userId: string): Promise<boolean>;
  hasFutureEventRegistrations(userId: string): Promise<boolean>;
}

/** Talep kuyruğu: silme işlemi (anonimleştirme + Auth silme) arka planda, insan onayıyla yürür. */
export interface DeletionRequestSink {
  /** `userId` ile İDEMPOTENT: aynı kullanıcı için açık talep varsa yenisini açmaz. */
  open(userId: string, plan: DeletionPlan, nowMs: number): Promise<{ created: boolean }>;
}

export interface DeletionDeps {
  readonly facts: DeletionFacts;
  readonly requests: DeletionRequestSink;
  readonly audit: AuditSink;
  readonly nowMs: () => number;
}

export async function requestAccountDeletionHandler(
  deps: DeletionDeps,
  auth: CallableAuth | null | undefined,
  _data: unknown,
): Promise<{ accepted: boolean; blockers: DeletionBlocker[]; alreadyRequested: boolean }> {
  const ctx = requireAuth(auth);
  const [pending, dues, regs] = await Promise.all([
    deps.facts.hasPendingPayments(ctx.uid),
    deps.facts.hasOutstandingDues(ctx.uid),
    deps.facts.hasFutureEventRegistrations(ctx.uid),
  ]);
  const plan = planAccountDeletion({
    userId: ctx.uid,
    hasPendingPayments: pending,
    hasOutstandingDues: dues,
    hasFutureEventRegistrations: regs,
  });
  if (!plan.canProceed) return { accepted: false, blockers: plan.blockers, alreadyRequested: false };

  const nowMs = deps.nowMs();
  const { created } = await deps.requests.open(ctx.uid, plan, nowMs);
  if (created) {
    await deps.audit.write(
      buildAuditEntry({
        actorId: ctx.uid,
        actorRole: ctx.role,
        action: "account.deletion_request",
        targetType: "user",
        targetId: ctx.uid,
        before: null,
        after: { delete: plan.delete.length, anonymize: plan.anonymize.length },
        nowMs,
      }),
    );
  }
  return { accepted: true, blockers: [], alreadyRequested: !created };
}
