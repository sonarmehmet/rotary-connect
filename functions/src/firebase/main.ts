import { randomUUID } from "node:crypto";
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { setGlobalOptions } from "firebase-functions/v2";
import { CallableRequest, HttpsError, onCall, onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { FirestoreEventTxRunner, FirestorePaymentTxRunner } from "../adapters/firestoreStores";
import { FirestoreEffectsTxRunner } from "../adapters/firestoreEffects";
import { EventRegistrationService } from "../events/service";
import { toCallableError } from "../handlers/callableError";
import {
  CallableAuth, cancelRegistrationHandler, recordManualPaymentHandler, reserveEventSpotHandler, startDonationHandler,
} from "../handlers/handlers";
import { Audience, Recipient, RecipientPage, sendAnnouncementHandler } from "../handlers/announce";
import { handleIyzicoWebhook } from "../handlers/iyzicoWebhook";
import { startDuePaymentHandler, startEventFeePaymentHandler } from "../handlers/payHandlers";
import { getDonationReceiptHandler, requestAccountDeletionHandler } from "../handlers/userHandlers";
import { runDueMaintenance, runExpireReservations, runReconcile } from "../jobs/scheduled";
import { DEFAULT_PREFS, NotificationPrefs } from "../notifications/notifications";
import { EffectsDeps, applyEffects } from "../payments/effects";
import { handleProviderEvent, sweepEffects } from "../payments/pipeline";
import { executeAccountDeletion } from "../privacy/executeDeletion";
import { requireAuth } from "../handlers/handlers";
import { IYZICO_SECRET_KEY, SECRETS, activeProvider, isLive, iyzico } from "./payConfig";
import { fsDb, timestampClock } from "./sdk";
import { stores } from "./stores";

/**
 * Firebase giriş noktası: tüm bağlantı burada, iş kuralı `src/` altındaki test edilmiş modüllerde.
 * DOĞRULANMAMIŞ: SDK bu ortamda kurulamadı; `npm install && npm run build` ilk derleme hatalarını verir.
 * Not: B'nin `adminOps` işleyicileri (assignRole, approve/endMembership, assignDues, issueRefund,
 * exportReport) için Firestore port uygulamaları HENÜZ bağlanmadı (bkz. docs/PROGRESS.md).
 */
setGlobalOptions({ region: "europe-west1", maxInstances: 10 });
initializeApp();

const RESERVATION_MINUTES = 15;

const db = getFirestore();
const s = stores(db, getAuth());
const fs = fsDb(db);
const nowMs = (): number => Date.now();
const newId = (): string => randomUUID();

const paymentRunner = new FirestorePaymentTxRunner(fs, timestampClock);
const eventSvc = new EventRegistrationService(new FirestoreEventTxRunner(fs, timestampClock));
const effects: EffectsDeps = {
  runner: new FirestoreEffectsTxRunner(fs, timestampClock),
  events: eventSvc,
  notifications: s.notifications,
  refunds: s.refundRequests,
  nowMs,
};

const provider = activeProvider;
const mode = (): "simulation" | "live" => (isLive() ? "live" : "simulation");

function toAuth(req: CallableRequest): CallableAuth | null {
  return req.auth ? { uid: req.auth.uid, token: req.auth.token as unknown as Record<string, unknown> } : null;
}

function callable<T>(fn: (auth: CallableAuth | null, data: unknown) => Promise<T>, secrets: typeof SECRETS = []) {
  return onCall({ secrets }, async (req) => {
    try {
      return await fn(toAuth(req), req.data);
    } catch (e) {
      if (e instanceof HttpsError) throw e; // doğrudan fırlatılan HttpsError olduğu gibi gider
      const c = toCallableError(e);
      if (c.code === "internal") console.error("callable hatası", e instanceof Error ? e.message : "bilinmiyor");
      throw new HttpsError(c.code, c.message, { reason: c.reason });
    }
  });
}

// ------------------------------------------------------------------ callable'lar
const eventDeps = { events: eventSvc, nowMs, reservationMinutes: RESERVATION_MINUTES };
export const reserveEventSpot = callable((a, d) => reserveEventSpotHandler(eventDeps, a, d));
export const cancelRegistration = callable((a, d) => cancelRegistrationHandler(eventDeps, a, d));

export const startDonation = callable(
  (a, d) => startDonationHandler({ payments: paymentRunner, provider: provider(), campaigns: s.campaigns, donations: s.donations, nowMs, mode: mode(), newId }, a, d),
  SECRETS,
);
export const startDuePayment = callable(
  (a, d) => startDuePaymentHandler({ payments: paymentRunner, provider: provider(), nowMs, mode: mode(), newId, dues: s.dues, partialEnabled: async () => (await db.collection("app_settings").doc("public").get()).data()?.["partialDuesEnabled"] === true }, a, d),
  SECRETS,
);
export const startEventFeePayment = callable(
  (a, d) => startEventFeePaymentHandler({ payments: paymentRunner, provider: provider(), nowMs, mode: mode(), newId, registrations: s.registrations }, a, d),
  SECRETS,
);
export const recordManualPayment = callable((a, d) =>
  recordManualPaymentHandler({ payments: paymentRunner, audit: s.audit, nowMs, onCollected: (p) => applyEffects(effects, [{ type: "collected", payment: p }]) }, a, d),
);
export const getDonationReceipt = callable((a, d) => getDonationReceiptHandler({ receipts: s.receipts }, a, d));
export const requestAccountDeletion = callable((a, d) =>
  requestAccountDeletionHandler({ facts: s.facts, requests: s.deletionRequests, audit: s.audit, nowMs }, a, d),
);

// Duyuru alıcıları: `all`/`members` Firestore'dan, `role` Auth claim taramasından.
async function recipientPage(audience: Audience, cursor: string | null, limit: number): Promise<RecipientPage> {
  const prefsOf = (d: FirebaseFirestore.DocumentData | undefined): NotificationPrefs => ({ ...DEFAULT_PREFS, ...(d?.["notificationPrefs"] ?? {}) });
  if (audience.type === "role") {
    const page = await getAuth().listUsers(limit, cursor ?? undefined);
    const hits = page.users.filter((u) => (u.customClaims?.["role"] ?? "registered_user") === audience.role);
    const snaps = await Promise.all(hits.map((u) => db.collection("users").doc(u.uid).get()));
    const recipients: Recipient[] = hits.map((u, i) => ({ userId: u.uid, prefs: prefsOf(snaps[i]?.data()) }));
    return { recipients, next: page.pageToken ?? null };
  }
  // Rol belgede tutulmaz: üyeler `club_members` (aktif) koleksiyonundan, herkes `users`'tan okunur.
  const members = audience.type === "members";
  let q = members
    ? db.collection("club_members").where("status", "==", "active").orderBy("__name__").limit(limit)
    : db.collection("users").orderBy("__name__").limit(limit);
  if (cursor) q = q.startAfter(cursor);
  const snaps = await q.get();
  const ids = snaps.docs.map((x) => (members ? String(x.data()["userId"]) : x.id));
  const users = await Promise.all(ids.map((id) => db.collection("users").doc(id).get()));
  return {
    recipients: ids.map((id, i) => ({ userId: id, prefs: prefsOf(users[i]?.data()) })),
    next: snaps.size < limit ? null : (snaps.docs[snaps.size - 1]?.id ?? null),
  };
}
export const sendAnnouncement = callable((a, d) =>
  sendAnnouncementHandler({ recipients: { page: recipientPage }, notifications: s.notifications, audit: s.audit, nowMs }, a, d),
);

/** YALNIZCA simülasyon: sistem yöneticisi bekleyen simüle ödemeyi sonuçlandırır (canlıda kapalı). */
export const simulatePaymentResult = callable(async (a, d) => {
  const ctx = requireAuth(a);
  if (isLive() || ctx.role !== "system_admin") throw new HttpsError("permission-denied", "İzin yok");
  const o = (d ?? {}) as { paymentId?: unknown; outcome?: unknown };
  if (typeof o.paymentId !== "string" || (o.outcome !== "succeeded" && o.outcome !== "failed")) throw new HttpsError("invalid-argument", "Geçersiz istek");
  const p = await paymentRunner.run((tx) => tx.getPayment(o.paymentId as string));
  if (!p || !p.simulated || !p.providerRef) throw new HttpsError("not-found", "Simüle ödeme bulunamadı");
  const r = await handleProviderEvent(paymentRunner, effects, {
    event: { providerRef: p.providerRef, status: o.outcome as "succeeded" | "failed", amountMinor: p.amountMinor, currency: p.currency },
    signatureValid: true, nowMs: nowMs(),
  });
  return { result: r.webhook.result, effectsFailed: r.effectsFailed };
});

// ------------------------------------------------------------------ webhook
export const iyzicoWebhook = onRequest({ secrets: SECRETS }, async (req, res) => {
  if (req.method !== "POST") { res.status(405).send("method"); return; }
  const out = await handleIyzicoWebhook(
    { secretKey: IYZICO_SECRET_KEY.value(), provider: iyzico(), payments: paymentRunner, effects, nowMs },
    req.header("x-iyz-signature-v3"),
    req.body,
  );
  res.status(out.httpStatus).send(out.httpStatus === 200 ? "OK" : "ERR");
});

// ------------------------------------------------------------------ zamanlanmış işler
const TZ = "Europe/Istanbul";
export const jobExpireReservations = onSchedule({ schedule: "every 5 minutes", timeZone: TZ }, async () => {
  await runExpireReservations(s.openEvents, eventSvc, nowMs(), RESERVATION_MINUTES);
});
export const jobDueMaintenance = onSchedule({ schedule: "every day 09:00", timeZone: TZ }, async () => {
  await runDueMaintenance(s.dueSource, s.dueSink, s.notifications, nowMs(), 3);
});
export const jobReconcile = onSchedule({ schedule: "every 10 minutes", timeZone: TZ, secrets: SECRETS }, async () => {
  if (!isLive()) return; // simülasyon ödemeleri otomatik sonuçlanmaz
  await runReconcile(paymentRunner, iyzico(), { nowMs: nowMs(), olderThanMs: 10 * 60_000, batchSize: 100, expireAfterMs: 24 * 3_600_000 });
});
export const jobSweepEffects = onSchedule({ schedule: "every 15 minutes", timeZone: TZ }, async () => {
  await sweepEffects(s.succeeded, effects, nowMs() - 3 * 24 * 3_600_000, 500);
});
export const jobProcessDeletions = onSchedule({ schedule: "every 60 minutes", timeZone: TZ }, async () => {
  const open = await db.collection("deletion_requests").where("status", "in", ["open", "blocked"]).limit(50).get();
  for (const d of open.docs) {
    const r = await executeAccountDeletion({ store: s.personal, auth: s.authAdmin, facts: s.facts }, d.id);
    await d.ref.update(r.done ? { status: "done", doneAt: new Date() } : { status: "blocked", blockers: r.blockers });
  }
});

// Yönetim paneli callable'ları (assignRole, approveMembership, endMembership, assignDues, issueRefund,
// exportReport): Firestore/Auth bağlantıları `../callables.ts` içinde.
export * from "../callables";
