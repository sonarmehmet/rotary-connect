import { HttpsError, onCall } from "firebase-functions/v2/https";
import { initializeApp, getApps } from "firebase-admin/app";
import { FirestoreAdminTxRunner, FirestoreAuditSink, FirestoreDuesTxRunner, FirestoreExportReader, FirestoreRefundTxRunner } from "./adapters/adminFirestore";
import { AdminSdkAuthRoles, AdminSdkFirestore, timestampClock } from "./adapters/sdk";
import {
  approveMembershipHandler, assignDuesHandler, assignRoleHandler, endMembershipHandler,
  exportReportHandler, issueRefundHandler,
} from "./handlers/adminOps";
import { CallableAuth } from "./handlers/handlers";
import { SECRETS, isLive, iyzico } from "./firebase/payConfig";
import { FirestoreEffectsTxRunner } from "./adapters/firestoreEffects";
import { FirestoreEventTxRunner } from "./adapters/firestoreStores";
import { EventRegistrationService } from "./events/service";
import { applyRefundEffects } from "./payments/refundEffects";
import { toCallableError } from "./handlers/callableError";

/**
 * Yönetim paneli callable sarmalayıcıları. İş mantığı `handlers/adminOps.ts`'dedir; burada yalnızca
 * SDK bağlantısı ve hata eşleme vardır. DOĞRULANMAMIŞ: emülatörde çalıştırılmadı.
 */
if (getApps().length === 0) initializeApp();

const REGION = "europe-west1";
let cache: ReturnType<typeof build> | undefined;

function build() {
  const db = new AdminSdkFirestore();
  const roles = new AdminSdkAuthRoles();
  const audit = new FirestoreAuditSink(db, timestampClock);
  const nowMs = (): number => Date.now();
  const refundEffects = {
    runner: new FirestoreEffectsTxRunner(db, timestampClock),
    events: new EventRegistrationService(new FirestoreEventTxRunner(db, timestampClock)),
    reservationMinutes: 15,
    nowMs,
  };
  return {
    admin: { store: new FirestoreAdminTxRunner(db, timestampClock, roles), audit, nowMs },
    dues: { dues: new FirestoreDuesTxRunner(db, timestampClock), audit, nowMs },
    refunds: {
      refunds: new FirestoreRefundTxRunner(db, timestampClock),
      audit,
      nowMs,
      onRefunded: async (p: import("./payments/repo").PaymentDoc, refundId: string, amount: number, full: boolean) => {
        await applyRefundEffects(refundEffects, p, refundId, amount, full);
      },
    },
    exports: { reader: new FirestoreExportReader(db, timestampClock), audit, nowMs },
  };
}
const deps = () => (cache ??= build());

function wrap<T>(run: (auth: CallableAuth | null, data: unknown) => Promise<T>, secrets: typeof SECRETS = []) {
  return onCall({ region: REGION, secrets }, async (request) => {
    try {
      const auth: CallableAuth | null = request.auth
        ? { uid: request.auth.uid, token: request.auth.token as unknown as Record<string, unknown> }
        : null;
      return await run(auth, request.data);
    } catch (e) {
      const err = toCallableError(e);
      throw new HttpsError(err.code, err.message, err.reason === null ? undefined : { reason: err.reason });
    }
  });
}

export const assignRole = wrap((a, d) => assignRoleHandler(deps().admin, a, d));
export const approveMembership = wrap((a, d) => approveMembershipHandler(deps().admin, a, d));
export const endMembership = wrap((a, d) => endMembershipHandler(deps().admin, a, d));
export const assignDues = wrap((a, d) => assignDuesHandler(deps().dues, a, d));
// Gerçek sağlayıcı ödemelerinde para iadesi iyzico'dan yapılır (canlı/sandbox modunda); simülasyonda yok.
export const issueRefund = wrap(
  (a, d) =>
    issueRefundHandler(
      {
        ...deps().refunds,
        ...(isLive()
          ? { providerRefund: async (p, amount, key) => { await iyzico().refund(p.providerRef ?? "", amount, key); } }
          : {}),
      },
      a,
      d,
    ),
  SECRETS,
);
export const exportReport = wrap((a, d) => exportReportHandler(deps().exports, a, d));
