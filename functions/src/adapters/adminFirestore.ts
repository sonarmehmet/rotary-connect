import { AuditEntry } from "../audit/audit";
import { AuditSink } from "../handlers/handlers";
import {
  AdminTx, AdminTxRunner, DuesTx, DuesTxRunner, ExportDueRow, ExportPaymentRow, ExportRange,
  ExportReader, RefundRow, RefundTx, RefundTxRunner,
} from "../handlers/adminOps";
import { Role } from "../lib/roles";
import { DueAssignment, MemberDoc } from "../members/members";
import { Clock, FsDb, FsQuery, FsSnap, FsTx } from "./fsTypes";
import { buildPaymentTx, encode, payFrom } from "./firestoreStores";

/** Koleksiyon adları (docs/DATA_MODEL.md). */
const MEMBERS = "club_members";
const DUES = "membership_dues";
const REFUNDS = "refunds";
const PAYMENTS = "payments";
const AUDIT = "audit_logs";

/**
 * Rol claim'i Firestore'da değil Firebase Auth'tadır. Gerçek uygulama (`adapters/sdk.ts`)
 * `getUser` / `setCustomUserClaims` / `listUsers` çağırır. Auth işlemi Firestore transaction'ının
 * parçası değildir: önce Firestore belgeleri, en sonda claim yazılır (bkz. FirestoreAdminTxRunner).
 */
export interface AuthRolePort {
  /** `null` = kullanıcı yok; claim yoksa `registered_user`. */
  getRole(userId: string): Promise<Role | null>;
  setRole(userId: string, role: Role): Promise<void>;
  countWithRole(role: Role): Promise<number>;
}

function memberFrom(s: FsSnap, clock: Clock): MemberDoc {
  const d = s.data();
  if (!s.exists || !d) throw new Error(`üyelik bulunamadı: ${s.id}`);
  const ms = (v: unknown): number | null => (v === null || v === undefined ? null : clock.toMs(v));
  return {
    userId: d["userId"] as string,
    memberNo: (d["memberNo"] as string | null | undefined) ?? null,
    status: d["status"] as MemberDoc["status"],
    requestedAtMs: ms(d["requestedAt"]) ?? 0,
    joinedAtMs: ms(d["joinedAt"]),
    approvedBy: (d["approvedBy"] as string | null | undefined) ?? null,
  };
}

function memberRow(m: MemberDoc, clock: Clock): Record<string, unknown> {
  return encode(
    {
      userId: m.userId, memberNo: m.memberNo, status: m.status,
      requestedAtMs: m.requestedAtMs, joinedAtMs: m.joinedAtMs, approvedBy: m.approvedBy,
    },
    clock,
  );
}

/**
 * Üyelik/rol transaction'ı. Firestore yazmaları transaction sonunda uygulanır; claim yazımı
 * (Auth) bu yüzden transaction BAŞARIYLA bittikten sonra yapılır. Claim yazımı başarısız olursa
 * üyelik kaydı güncel, claim eski kalır (bilinen sınır; mutabakat/yeniden deneme C'de).
 */
export class FirestoreAdminTxRunner implements AdminTxRunner {
  constructor(private readonly db: FsDb, private readonly clock: Clock, private readonly auth: AuthRolePort) {}

  async run<T>(fn: (tx: AdminTx) => Promise<T>): Promise<T> {
    const { db, clock, auth } = this;
    const claims: { userId: string; role: Role }[] = [];
    const out = await db.runTransaction(async (fs: FsTx) => {
      claims.length = 0; // transaction yeniden denenirse birikmesin
      const members = db.collection(MEMBERS);
      const tx: AdminTx = {
        async getMember(id) {
          const s = await fs.getDoc(members.doc(id));
          return s.exists ? memberFrom(s, clock) : null;
        },
        async memberNoTaken(memberNo, exceptId) {
          const snaps = await fs.getQuery(members.where("memberNo", "==", memberNo).limit(2));
          return snaps.some((s) => s.id !== exceptId);
        },
        async saveMember(id, doc) {
          fs.set(members.doc(id), memberRow(doc, clock));
        },
        getUserRole: (userId) => auth.getRole(userId),
        async setUserRole(userId, role) {
          claims.push({ userId, role });
        },
        countUsersWithRole: (role) => auth.countWithRole(role),
      };
      return fn(tx);
    });
    for (const c of claims) await auth.setRole(c.userId, c.role);
    return out;
  }
}

/** Toplu aidat. Firestore transaction en çok 500 yazma kabul eder; fazlası reddedilir. */
export const MAX_DUES_PER_CALL = 450;

export class FirestoreDuesTxRunner implements DuesTxRunner {
  constructor(private readonly db: FsDb, private readonly clock: Clock) {}

  run<T>(fn: (tx: DuesTx) => Promise<T>): Promise<T> {
    const { db, clock } = this;
    return db.runTransaction(async (fs: FsTx) => {
      const members = db.collection(MEMBERS);
      const dues = db.collection(DUES);
      const tx: DuesTx = {
        async listActiveMemberIds() {
          const snaps = await fs.getQuery(members.where("status", "==", "active"));
          return snaps.map((s) => s.id);
        },
        async getMemberStatus(id) {
          const s = await fs.getDoc(members.doc(id));
          const st = s.data()?.["status"];
          return s.exists && typeof st === "string" ? (st as MemberDoc["status"]) : null;
        },
        async assignedMemberIds(periodId) {
          const snaps = await fs.getQuery(dues.where("periodId", "==", periodId));
          return new Set(snaps.map((s) => String(s.data()?.["memberId"] ?? "")));
        },
        async createDues(items: readonly DueAssignment[]) {
          if (items.length > MAX_DUES_PER_CALL) {
            throw new Error(`tek çağrıda en çok ${MAX_DUES_PER_CALL} borç atanabilir`);
          }
          // Okumalar yazmalardan önce: borç belgesi `userId` taşır.
          const userIds = new Map<string, string>();
          for (const it of items) {
            const s = await fs.getDoc(members.doc(it.memberId));
            userIds.set(it.memberId, String(s.data()?.["userId"] ?? ""));
          }
          for (const it of items) {
            fs.set(
              dues.doc(),
              encode(
                {
                  userId: userIds.get(it.memberId),
                  memberId: it.memberId,
                  periodId: it.periodId,
                  periodLabel: it.periodLabel,
                  amountMinor: it.amountMinor,
                  currency: it.currency,
                  paidMinor: 0,
                  dueDateMs: it.dueDateMs,
                  status: "unpaid",
                  allowPartial: it.allowPartial,
                  createdBy: it.createdBy,
                  createdAtMs: it.createdAtMs,
                },
                clock,
              ),
            );
          }
        },
      };
      return fn(tx);
    });
  }
}

export class FirestoreRefundTxRunner implements RefundTxRunner {
  constructor(private readonly db: FsDb, private readonly clock: Clock) {}

  run<T>(fn: (tx: RefundTx) => Promise<T>): Promise<T> {
    const { db, clock } = this;
    return db.runTransaction((fs: FsTx) => {
      const refunds = db.collection(REFUNDS);
      const tx: RefundTx = {
        ...buildPaymentTx(db, clock, fs),
        async createRefund(r) {
          const ref = refunds.doc();
          fs.set(ref, encode({ ...r }, clock));
          return ref.id;
        },
      };
      return fn(tx);
    });
  }
}

/** Denetim kaydı: `audit_logs` (değiştirilemez; yalnızca ekleme). */
export class FirestoreAuditSink implements AuditSink {
  constructor(private readonly db: FsDb, private readonly clock: Clock) {}

  async write(entry: AuditEntry): Promise<void> {
    const { db, clock } = this;
    await db.runTransaction(async (fs: FsTx) => {
      fs.set(db.collection(AUDIT).doc(), encode({ ...entry }, clock));
    });
  }
}

function rangeQuery(q: FsQuery, range: ExportRange, field: string, clock: Clock, limit: number): FsQuery {
  let out = q;
  if (range.fromMs !== null) out = out.where(field, ">=", clock.fromMs(range.fromMs));
  if (range.toMs !== null) out = out.where(field, "<=", clock.fromMs(range.toMs));
  return out.limit(limit);
}

/** Dışa aktarma okuyucusu: salt okunur transaction ile; sıralama kimlik sırasına bağlı değildir. */
export class FirestoreExportReader implements ExportReader {
  constructor(private readonly db: FsDb, private readonly clock: Clock) {}

  private read<T>(col: string, field: string, range: ExportRange, limit: number, map: (s: FsSnap) => T): Promise<T[]> {
    const { db, clock } = this;
    return db.runTransaction(async (fs: FsTx) => {
      const snaps = await fs.getQuery(rangeQuery(db.collection(col), range, field, clock, limit));
      return snaps.map(map);
    });
  }

  payments(range: ExportRange, limit: number): Promise<ExportPaymentRow[]> {
    const clock = this.clock;
    return this.read(PAYMENTS, "createdAt", range, limit, (s) => {
      const p = payFrom(s, clock);
      return {
        id: p.id, kind: p.kind, refId: p.refId, amountMinor: p.amountMinor, currency: p.currency,
        status: p.status, provider: p.provider, manual: p.manual, simulated: p.simulated,
        refundedMinor: p.refundedMinor, createdAtMs: p.createdAtMs, succeededAtMs: p.succeededAtMs,
      };
    });
  }

  dues(range: ExportRange, limit: number): Promise<ExportDueRow[]> {
    const clock = this.clock;
    return this.read(DUES, "dueDate", range, limit, (s) => {
      const d = s.data() ?? {};
      return {
        id: s.id,
        memberId: String(d["memberId"] ?? ""),
        periodLabel: String(d["periodLabel"] ?? ""),
        amountMinor: Number(d["amountMinor"] ?? 0),
        paidMinor: Number(d["paidMinor"] ?? 0),
        currency: String(d["currency"] ?? "TRY"),
        dueDateMs: clock.toMs(d["dueDate"]),
        status: String(d["status"] ?? ""),
        allowPartial: d["allowPartial"] === true,
      };
    });
  }

  refunds(range: ExportRange, limit: number): Promise<RefundRow[]> {
    const clock = this.clock;
    return this.read(REFUNDS, "createdAt", range, limit, (s) => {
      const d = s.data() ?? {};
      return {
        id: s.id,
        paymentId: String(d["paymentId"] ?? ""),
        kind: d["kind"] as RefundRow["kind"],
        amountMinor: Number(d["amountMinor"] ?? 0),
        currency: String(d["currency"] ?? "TRY"),
        status: d["status"] as RefundRow["status"],
        reason: String(d["reason"] ?? ""),
        requestedBy: String(d["requestedBy"] ?? ""),
        createdAtMs: clock.toMs(d["createdAt"]),
      };
    });
  }
}
