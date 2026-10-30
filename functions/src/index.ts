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
