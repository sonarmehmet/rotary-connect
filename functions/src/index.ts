/**
 * Cloud Functions giriş noktası.
 * Aşama 4+: firebase-functions / firebase-admin bağımlılıkları eklenecek ve
 * callable'lar (createPayment, webhook, reserveEventSpot, ...) burada export edilecek.
 * Aşama 2'de yalnızca doğrulanabilir saf iş mantığı bulunur.
 */
export { decideWebhook, canTransition, countsAsCollected } from "./payments/paymentState";
export { SimulatedProvider } from "./payments/provider";
export { requireRole, parseRole, PermissionDeniedError } from "./lib/roles";
export { assertValidMoney, moneyEquals } from "./lib/money";
