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
export {
  requestMembership,
  approveMembership as approveMembershipRule,
  endMembership as endMembershipRule,
  assignDues as assignDuesRule,
} from "./members/members";
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
  cancelDueHandler,
  issueRefundHandler,
  exportReportHandler,
} from "./handlers/adminOps";
export type { AdminTx, AdminTxRunner, DuesTx, DuesTxRunner, RefundTx, RefundTxRunner, ExportReader } from "./handlers/adminOps";
export { FirestoreEffectsTxRunner } from "./adapters/firestoreEffects";
export { handleProviderEvent, sweepEffects } from "./payments/pipeline";
export type { PipelineResult, SucceededPaymentSource, SweepReport } from "./payments/pipeline";
export { startDuePaymentHandler, startEventFeePaymentHandler } from "./handlers/payHandlers";
export type { DueReader, RegistrationReader, PayHandlerDeps, PayResult } from "./handlers/payHandlers";
export { getDonationReceiptHandler, requestAccountDeletionHandler } from "./handlers/userHandlers";
export type { Receipt, ReceiptReader, ReceiptRow, DeletionDeps, DeletionFacts, DeletionRequestSink } from "./handlers/userHandlers";
export { runExpireReservations, runDueMaintenance, runReconcile } from "./jobs/scheduled";
export type { OpenEventSource, DueSource, DueSink, DueRow, ExpireReport, DueJobReport } from "./jobs/scheduled";
export { FirestoreAdminTxRunner, FirestoreDuesTxRunner, FirestoreRefundTxRunner, FirestoreExportReader, FirestoreAuditSink } from "./adapters/adminFirestore";
export type { AuthRolePort } from "./adapters/adminFirestore";
export { IyzicoProvider, iyzicoHppSignature, verifyIyzicoHppSignature, parseIyzicoWebhook, minorToPrice, priceToMinor } from "./payments/iyzico";
export type { IyzicoHttp, IyzicoBuyer, IyzicoOptions, IyzicoWebhookPayload } from "./payments/iyzico";
export { handleIyzicoWebhook } from "./handlers/iyzicoWebhook";
export type { IyzicoWebhookDeps } from "./handlers/iyzicoWebhook";
export type { ProviderResult } from "./payments/provider";
export { executeAccountDeletion, ANONYMIZE_PATCHES } from "./privacy/executeDeletion";
export type { PersonalDataStore, AuthAdmin, DeletionResult } from "./privacy/executeDeletion";
export { applyRefundEffects, sweepRefundEffects } from "./payments/refundEffects";
export type { RefundEffectsDeps, RefundSweepSource, RefundSweepRow, RefundSweepReport } from "./payments/refundEffects";
export { FirestoreRefundSweepSource } from "./adapters/adminFirestore";
