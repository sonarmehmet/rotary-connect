import { Auth } from "firebase-admin/auth";
import { Firestore, Timestamp } from "firebase-admin/firestore";
import { AuditEntry } from "../audit/audit";
import { buildNotification, NotificationItem, NotificationWriter } from "../notifications/notifications";
import { CampaignInfo, CampaignReader, DonationRecorder, PendingDonation } from "../handlers/handlers";
import { DueReader, RegistrationReader } from "../handlers/payHandlers";
import { DeletionFacts, DeletionRequestSink, ReceiptReader, ReceiptRow } from "../handlers/userHandlers";
import { DueRow, DueSink, DueSource, OpenEventSource } from "../jobs/scheduled";
import { PaymentDoc } from "../payments/repo";
import { SucceededPaymentSource } from "../payments/pipeline";
import { RefundRequestSink } from "../payments/effects";
import { AuthAdmin, PersonalDataStore } from "../privacy/executeDeletion";
import { timestampClock as clock } from "./sdk";

/** Firestore'a bağlı port uygulamaları. DOĞRULANMAMIŞ (SDK kurulu değil, emülatörde denenmedi). */
const ms = (v: unknown): number => clock.toMs(v);
const ts = (n: number): Timestamp => Timestamp.fromMillis(n);

export function stores(db: Firestore, auth: Auth) {
  const audit = {
    async write(e: AuditEntry): Promise<void> {
      const { createdAtMs, ...rest } = e;
      await db.collection("audit_logs").add({ ...rest, createdAt: ts(createdAtMs) });
    },
  };

  const notifications: NotificationWriter = {
    async createIfAbsent(items: readonly NotificationItem[]): Promise<void> {
      for (const item of items) {
        const { createdAtMs, ...rest } = item.doc;
        try {
          await db.collection("notifications").doc(item.id).create({ ...rest, createdAt: ts(createdAtMs) });
        } catch (e) {
          if ((e as { code?: number }).code !== 6) throw e; // 6 = ALREADY_EXISTS → idempotent
        }
      }
    },
  };

  const campaigns: CampaignReader = {
    async get(id): Promise<CampaignInfo | null> {
      const s = await db.collection("donation_campaigns").doc(id).get();
      const d = s.data();
      return s.exists && d ? { status: d["status"], currency: d["currency"] ?? "TRY" } : null;
    },
  };

  const donations: DonationRecorder = {
    async createPending(d: PendingDonation): Promise<void> {
      // Belirli kimlik: tekrar çağrı aynı kaydı yazar (çift bağış kaydı oluşmaz).
      await db.collection("donations").doc(`don_${d.paymentId}`).set({
        campaignId: d.campaignId,
        paymentId: d.paymentId,
        userId: d.userId,
        donor: { name: d.donor.name, email: d.donor.email, anonymous: d.donor.anonymous },
        amountMinor: d.amountMinor,
        currency: d.currency,
        status: "pending",
        createdAt: ts(d.nowMs),
      });
    },
  };

  const dues: DueReader = {
    async get(id) {
      const s = await db.collection("membership_dues").doc(id).get();
      const d = s.data();
      if (!s.exists || !d) return null;
      return {
        userId: d["userId"], currency: d["currency"], amountMinor: d["amountMinor"], paidMinor: d["paidMinor"] ?? 0,
        dueDateMs: ms(d["dueDate"]), cancelled: d["status"] === "cancelled", refunded: d["status"] === "refunded",
        allowPartial: d["allowPartial"] ?? false,
      };
    },
  };

  const registrations: RegistrationReader = {
    async get(id) {
      const s = await db.collection("event_registrations").doc(id).get();
      const d = s.data();
      if (!s.exists || !d) return null;
      return {
        id: s.id, eventId: d["eventId"], userId: d["userId"], participant: d["participant"], status: d["status"],
        paymentId: d["paymentId"] ?? null, reservedUntilMs: d["reservedUntil"] ? ms(d["reservedUntil"]) : null,
        waitlistPosition: d["waitlistPosition"] ?? null, createdAtMs: ms(d["createdAt"]),
        confirmedAtMs: d["confirmedAt"] ? ms(d["confirmedAt"]) : null,
      };
    },
    async eventFee(eventId) {
      const d = (await db.collection("events").doc(eventId).get()).data();
      return d ? { feeMinor: d["feeMinor"] ?? 0, currency: d["currency"] ?? "TRY" } : null;
    },
  };

  const receipts: ReceiptReader = {
    async getByDonationId(id): Promise<ReceiptRow | null> {
      const s = await db.collection("donations").doc(id).get();
      const d = s.data();
      if (!s.exists || !d) return null;
      const p = (await db.collection("payments").doc(d["paymentId"]).get()).data();
      return {
        id: s.id, paymentId: d["paymentId"], userId: d["userId"] ?? null, donorEmail: d["donor"]?.email ?? null,
        donorName: d["donor"]?.name ?? "", anonymous: d["donor"]?.anonymous === true, amountMinor: d["amountMinor"],
        currency: d["currency"], status: d["status"], receiptNo: d["receiptNo"] ?? null, campaignId: d["campaignId"] ?? null,
        simulated: p?.["simulated"] === true, createdAtMs: ms(d["createdAt"]),
      };
    },
  };

  const exists = async (col: string, ...where: [string, FirebaseFirestore.WhereFilterOp, unknown][]): Promise<boolean> => {
    let q: FirebaseFirestore.Query = db.collection(col);
    for (const [f, o, v] of where) q = q.where(f, o, v);
    return !(await q.limit(1).get()).empty;
  };
  const facts: DeletionFacts = {
    hasPendingPayments: (u) => exists("payments", ["userId", "==", u], ["status", "in", ["created", "pending"]]),
    hasOutstandingDues: (u) => exists("membership_dues", ["userId", "==", u], ["status", "in", ["unpaid", "partially_paid", "overdue"]]),
    hasFutureEventRegistrations: (u) => exists("event_registrations", ["userId", "==", u], ["status", "in", ["reserved", "confirmed", "waitlisted"]]),
  };

  const deletionRequests: DeletionRequestSink = {
    async open(userId, plan, nowMs) {
      const ref = db.collection("deletion_requests").doc(userId);
      try {
        await ref.create({ userId, status: "open", blockers: plan.blockers, createdAt: ts(nowMs) });
        return { created: true };
      } catch (e) {
        if ((e as { code?: number }).code === 6) return { created: false };
        throw e;
      }
    },
  };

  const refundRequests: RefundRequestSink = {
    async request(p: PaymentDoc, reason: string): Promise<void> {
      try {
        await db.collection("refund_requests").doc(p.id).create({
          paymentId: p.id, reason, amountMinor: p.amountMinor, currency: p.currency, status: "open", createdAt: Timestamp.now(),
        });
      } catch (e) {
        if ((e as { code?: number }).code !== 6) throw e;
      }
    },
  };

  const succeeded: SucceededPaymentSource = {
    async listSucceededSince(sinceMs, limit) {
      const snaps = await db.collection("payments").where("status", "==", "succeeded").where("succeededAt", ">=", ts(sinceMs)).limit(limit).get();
      return snaps.docs.map((s) => {
        const d = s.data();
        return {
          id: s.id, kind: d["kind"], refId: d["refId"], userId: d["userId"] ?? null, amountMinor: d["amountMinor"], currency: d["currency"],
          status: d["status"], provider: d["provider"], providerRef: d["providerRef"] ?? null, simulated: d["simulated"] === true,
          idempotencyKey: d["idempotencyKey"], manual: d["manual"] === true, recordedBy: d["recordedBy"] ?? null, note: d["note"] ?? null,
          refundedMinor: d["refundedMinor"] ?? 0, createdAtMs: ms(d["createdAt"]), updatedAtMs: ms(d["updatedAt"]),
          succeededAtMs: d["succeededAt"] ? ms(d["succeededAt"]) : null, failureCode: d["failureCode"] ?? null, flag: d["flag"] ?? null,
        } as unknown as PaymentDoc;
      });
    },
  };

  const openEvents: OpenEventSource = {
    async listEventIdsWithReservations(limit) {
      const snaps = await db.collection("events").where("reservedCount", ">", 0).limit(limit).get();
      return snaps.docs.map((s) => s.id);
    },
  };

  const dueSource: DueSource = {
    async listOpenDues(cursor, limit) {
      let q = db.collection("membership_dues").where("status", "in", ["unpaid", "partially_paid", "overdue"]).orderBy("__name__").limit(limit);
      if (cursor) q = q.startAfter(cursor);
      const snaps = await q.get();
      const rows: DueRow[] = snaps.docs.map((s) => {
        const d = s.data();
        return {
          id: s.id, userId: d["userId"], status: d["status"], reminderSent: d["reminderSentAt"] != null, amountMinor: d["amountMinor"],
          paidMinor: d["paidMinor"] ?? 0, dueDateMs: ms(d["dueDate"]), cancelled: false, refunded: false, allowPartial: d["allowPartial"] ?? false,
        };
      });
      return { rows, next: snaps.size < limit ? null : (snaps.docs[snaps.size - 1]?.id ?? null) };
    },
  };
  const dueSink: DueSink = {
    setStatus: async (id, status) => void (await db.collection("membership_dues").doc(id).update({ status })),
    markReminderSent: async (id, nowMs) => void (await db.collection("membership_dues").doc(id).update({ reminderSentAt: ts(nowMs) })),
  };

  const personal: PersonalDataStore = {
    async anonymize(collection, userId, patch) {
      const snaps = await db.collection(collection).where("userId", "==", userId).get();
      for (let i = 0; i < snaps.docs.length; i += 400) {
        const b = db.batch();
        snaps.docs.slice(i, i + 400).forEach((s) => b.update(s.ref, patch));
        await b.commit();
      }
      return snaps.size;
    },
    async deleteWhereUser(collection, userId) {
      const snaps = await db.collection(collection).where("userId", "==", userId).get();
      for (let i = 0; i < snaps.docs.length; i += 400) {
        const b = db.batch();
        snaps.docs.slice(i, i + 400).forEach((s) => b.delete(s.ref));
        await b.commit();
      }
      return snaps.size;
    },
    deleteUserDoc: async (userId) => void (await db.collection("users").doc(userId).delete()),
  };
  const authAdmin: AuthAdmin = {
    async deleteUser(userId) {
      try {
        await auth.deleteUser(userId);
      } catch (e) {
        if ((e as { code?: string }).code !== "auth/user-not-found") throw e;
      }
    },
  };

  return {
    audit, notifications, campaigns, donations, dues, registrations, receipts, facts, deletionRequests,
    refundRequests, succeeded, openEvents, dueSource, dueSink, personal, authAdmin, buildNotification,
  };
}
