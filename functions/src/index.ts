/**
 * Cloud Functions giriş noktası.
 * Şu an yalnızca doğrulanabilir saf iş mantığı dışa aktarılır. firebase-admin /
 * firebase-functions bağımlılıkları eklenince (ağ erişimi olan makinede) callable ve HTTP
 * sarmalayıcıları `src/handlers/` altında bu mantığı çağıracak (bkz. docs/DATA_MODEL.md sözleşmesi).
 */
export { decideWebhook, canTransition, countsAsCollected } from "./payments/paymentState";
export { SimulatedProvider } from "./payments/provider";
export { planRefund } from "./payments/refunds";
export { resolveDonationAmount, resolveEventFee } from "./payments/amounts";
export { buildManualPayment } from "./payments/manual";
export { requireRole, parseRole, PermissionDeniedError } from "./lib/roles";
export { assertValidMoney, moneyEquals } from "./lib/money";
export { DomainError } from "./lib/errors";
export { EventRegistrationService } from "./events/service";
export { decideReserve, remainingSpots } from "./events/capacity";
export { deriveDueStatus, resolveDuePayment, applyPayment } from "./dues/dues";
export { buildAuditEntry, redact } from "./audit/audit";
export { startPayment, idempotencyKeyFor } from "./payments/startPayment";
export { processWebhook } from "./payments/webhook";
export { reconcilePending } from "./payments/reconcile";
export { aggregateByDay, campaignVerifiedTotal, istanbulDay } from "./reports/aggregates";
export { constantTimeEqual } from "./lib/safeEqual";
export { requestMembership, approveMembership, endMembership, assignDues } from "./members/members";
export { buildNotification, shouldSend, dueReminderDue, DEFAULT_PREFS } from "./notifications/notifications";
export { planAccountDeletion, anonymizeRecord } from "./privacy/deletion";
export { FirestoreEventTxRunner, FirestorePaymentTxRunner } from "./adapters/firestoreStores";
export type { FsDb, FsTx, Clock } from "./adapters/fsTypes";
export { recordManualPayment } from "./payments/manual";
export { toCallableError } from "./handlers/callableError";
export {
  requireAuth,
  reserveEventSpotHandler,
  cancelRegistrationHandler,
  startDonationHandler,
  recordManualPaymentHandler,
} from "./handlers/handlers";
export type { CallableAuth, AuthContext, AuditSink, CampaignReader, DonationRecorder } from "./handlers/handlers";
export { sendAnnouncementHandler, containsSensitive, ANNOUNCE_ROUTES } from "./handlers/announce";
export type { Audience, RecipientReader, NotificationWriter } from "./handlers/announce";
export { applyCollected, applyFailed, applyEffects } from "./payments/effects";
export type { EffectsDeps, EffectsTx, EffectsTxRunner, RefundRequestSink } from "./payments/effects";
export {
  assignRoleHandler,
  approveMembershipHandler,
  endMembershipHandler,
  assignDuesHandler,
  issueRefundHandler,
  exportReportHandler,
} from "./handlers/adminOps";
export type { AdminTx, AdminTxRunner, DuesTx, DuesTxRunner, RefundTx, RefundTxRunner, ExportReader } from "./handlers/adminOps";
