import { HttpsError, onCall } from "firebase-functions/v2/https";
import { initializeApp, getApps } from "firebase-admin/app";
import { FirestoreAdminTxRunner, FirestoreAuditSink, FirestoreDuesTxRunner, FirestoreExportReader, FirestoreRefundTxRunner } from "./adapters/adminFirestore";
import { AdminSdkAuthRoles, AdminSdkFirestore, timestampClock } from "./adapters/sdk";
import {
  approveMembershipHandler, assignDuesHandler, assignRoleHandler, endMembershipHandler,
  exportReportHandler, issueRefundHandler,
} from "./handlers/adminOps";
import { CallableAuth } from "./handlers/handlers";
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
  return {
    admin: { store: new FirestoreAdminTxRunner(db, timestampClock, roles), audit, nowMs },
    dues: { dues: new FirestoreDuesTxRunner(db, timestampClock), audit, nowMs },
    refunds: { refunds: new FirestoreRefundTxRunner(db, timestampClock), audit, nowMs },
    exports: { reader: new FirestoreExportReader(db, timestampClock), audit, nowMs },
  };
}
const deps = () => (cache ??= build());

function wrap<T>(run: (auth: CallableAuth | null, data: unknown) => Promise<T>) {
  return onCall({ region: REGION }, async (request) => {
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
export const issueRefund = wrap((a, d) => issueRefundHandler(deps().refunds, a, d));
export const exportReport = wrap((a, d) => exportReportHandler(deps().exports, a, d));
