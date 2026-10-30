import { describe, expect, it } from "vitest";
import { AuditEntry } from "../audit/audit";
import { DueAssignment, MemberDoc } from "../members/members";
import { Role } from "../lib/roles";
import { PaymentDoc } from "../payments/repo";
import {
  AdminTx,
  DuesTx,
  ExportPaymentRow,
  RefundRow,
  RefundTx,
  approveMembershipHandler,
  assignDuesHandler,
  assignRoleHandler,
  endMembershipHandler,
  exportReportHandler,
  issueRefundHandler,
  periodIdFor,
} from "./adminOps";
import { toCallableError } from "./callableError";
import { CallableAuth } from "./handlers";

const NOW = 1_800_000_000_000;
const DAY = 86_400_000;
const authAs = (uid: string, role?: string): CallableAuth => ({ uid, token: role === undefined ? {} : { role } });
const ADMIN = authAs("admin1", "system_admin");
const FIN = authAs("fin1", "finance_manager");

async function failure(p: Promise<unknown>): Promise<string> {
  try {
    await p;
    return "no-error";
  } catch (e) {
    const c = toCallableError(e);
    return `${c.code}:${c.reason ?? ""}`;
  }
}

// --------------------------------------------------------------- üyelik / rol

function memberDoc(userId: string, status: MemberDoc["status"], memberNo: string | null = null): MemberDoc {
  return { userId, memberNo, status, requestedAtMs: NOW - DAY, joinedAtMs: null, approvedBy: null };
}

function adminSetup(roles: Record<string, Role>, members: Record<string, MemberDoc>) {
  const audit: AuditEntry[] = [];
  const claims = { ...roles };
  const docs = { ...members };
  const tx: AdminTx = {
    getMember: async (id) => docs[id] ?? null,
    memberNoTaken: async (no, except) =>
      Object.entries(docs).some(([id, m]) => id !== except && m.memberNo?.toLowerCase() === no.toLowerCase()),
    saveMember: async (id, d) => void (docs[id] = d),
    getUserRole: async (u) => claims[u] ?? null,
    setUserRole: async (u, r) => void (claims[u] = r),
    countUsersWithRole: async (r) => Object.values(claims).filter((x) => x === r).length,
  };
  const deps = {
    store: { run: async <T>(fn: (t: AdminTx) => Promise<T>) => fn(tx) },
    audit: { write: async (e: AuditEntry) => void audit.push(e) },
    nowMs: () => NOW,
  };
  return { deps, audit, claims, docs };
}

describe("assignRole", () => {
  const base = () =>
    adminSetup(
      { admin1: "system_admin", u1: "registered_user", u2: "club_member", u3: "content_manager" },
      {},
    );

  it("yalnızca sistem yöneticisi atayabilir (içerik ve finans reddedilir)", async () => {
    const s = base();
    expect(await failure(assignRoleHandler(s.deps, authAs("x", "content_manager"), { userId: "u1", role: "finance_manager" }))).toBe("permission-denied:");
    expect(await failure(assignRoleHandler(s.deps, FIN, { userId: "u1", role: "finance_manager" }))).toBe("permission-denied:");
    expect(await failure(assignRoleHandler(s.deps, null, { userId: "u1", role: "finance_manager" }))).toBe("unauthenticated:login_required");
    expect(s.claims["u1"]).toBe("registered_user");
  });

  it("club_member elle atanamaz (girdi doğrulama)", async () => {
    const s = base();
    expect(await failure(assignRoleHandler(s.deps, ADMIN, { userId: "u1", role: "club_member" }))).toBe("invalid-argument:invalid_role");
  });

  it("başarılı atama claim'i değiştirir ve denetim kaydı yazar", async () => {
    const s = base();
    const out = await assignRoleHandler(s.deps, ADMIN, { userId: "u1", role: "finance_manager" });
    expect(out).toEqual({ userId: "u1", role: "finance_manager" });
    expect(s.claims["u1"]).toBe("finance_manager");
    expect(s.audit).toHaveLength(1);
    expect(s.audit[0]).toMatchObject({ action: "role.assign", targetId: "u1", before: { role: "registered_user" }, after: { role: "finance_manager" } });
  });

  it("olmayan kullanıcı, aynı rol ve üyelik akışı kuralları", async () => {
    const s = base();
    expect(await failure(assignRoleHandler(s.deps, ADMIN, { userId: "yok", role: "content_manager" }))).toBe("not-found:user_not_found");
    expect(await failure(assignRoleHandler(s.deps, ADMIN, { userId: "u3", role: "content_manager" }))).toBe("failed-precondition:same_role");
    expect(await failure(assignRoleHandler(s.deps, ADMIN, { userId: "u2", role: "registered_user" }))).toBe("failed-precondition:use_membership_flow");
    // üye, yönetici role yükseltilebilir
    await assignRoleHandler(s.deps, ADMIN, { userId: "u2", role: "content_manager" });
    expect(s.claims["u2"]).toBe("content_manager");
    expect(s.audit).toHaveLength(1); // hatalar denetim yazmaz
  });

  it("son sistem yöneticisi düşürülemez; ikinci yönetici varsa düşürülebilir", async () => {
    const s = base();
    expect(await failure(assignRoleHandler(s.deps, ADMIN, { userId: "admin1", role: "content_manager" }))).toBe("failed-precondition:last_admin");
    await assignRoleHandler(s.deps, ADMIN, { userId: "u1", role: "system_admin" });
    await assignRoleHandler(s.deps, ADMIN, { userId: "admin1", role: "content_manager" });
    expect(s.claims["admin1"]).toBe("content_manager");
  });
});

describe("üyelik onayı / sonlandırma", () => {
  const base = () =>
    adminSetup(
      { admin1: "system_admin", u1: "registered_user", u2: "club_member", u3: "content_manager", u4: "registered_user" },
      {
        m1: memberDoc("u1", "pending"),
        m2: memberDoc("u2", "active", "ÜY-0002"),
        m3: memberDoc("u3", "pending"),
        m4: memberDoc("u4", "pending"),
      },
    );

  it("yalnızca sistem yöneticisi", async () => {
    const s = base();
    expect(await failure(approveMembershipHandler(s.deps, FIN, { memberId: "m1", memberNo: "ÜY-1" }))).toBe("permission-denied:");
    expect(await failure(endMembershipHandler(s.deps, FIN, { memberId: "m2", to: "resigned" }))).toBe("permission-denied:");
  });

  it("onay: durum aktif, üye no yazılır, claim club_member olur, denetim kaydı", async () => {
    const s = base();
    const out = await approveMembershipHandler(s.deps, ADMIN, { memberId: "m1", memberNo: " ÜY-0001 " });
    expect(out).toEqual({ memberId: "m1", memberNo: "ÜY-0001", role: "club_member" });
    expect(s.docs["m1"]).toMatchObject({ status: "active", memberNo: "ÜY-0001", approvedBy: "admin1", joinedAtMs: NOW });
    expect(s.claims["u1"]).toBe("club_member");
    expect(s.audit[0]).toMatchObject({ action: "membership.approve", targetId: "m1", after: { status: "active" } });
  });

  it("yönetici rolü onayda korunur", async () => {
    const s = base();
    const out = await approveMembershipHandler(s.deps, ADMIN, { memberId: "m3", memberNo: "ÜY-0003" });
    expect(out.role).toBe("content_manager");
    expect(s.claims["u3"]).toBe("content_manager");
  });

  it("hatalar: bulunamadı, bekleyen değil, boş/mükerrer üye no", async () => {
    const s = base();
    expect(await failure(approveMembershipHandler(s.deps, ADMIN, { memberId: "yok", memberNo: "X-1" }))).toBe("not-found:member_not_found");
    expect(await failure(approveMembershipHandler(s.deps, ADMIN, { memberId: "m2", memberNo: "X-1" }))).toBe("failed-precondition:not_pending");
    expect(await failure(approveMembershipHandler(s.deps, ADMIN, { memberId: "m1", memberNo: "   " }))).toMatch(/^invalid-argument:/);
    expect(await failure(approveMembershipHandler(s.deps, ADMIN, { memberId: "m1", memberNo: "üy-0002" }))).toBe("already-exists:member_no_taken");
    expect(s.docs["m1"]?.status).toBe("pending");
    expect(s.claims["u1"]).toBe("registered_user");
    expect(s.audit).toHaveLength(0);
  });

  it("sonlandırma: rol registered_user'a düşer, yalnızca aktif üyelik", async () => {
    const s = base();
    const out = await endMembershipHandler(s.deps, ADMIN, { memberId: "m2", to: "suspended" });
    expect(out).toEqual({ memberId: "m2", status: "suspended", role: "registered_user" });
    expect(s.claims["u2"]).toBe("registered_user");
    expect(s.audit[0]).toMatchObject({ action: "membership.end", after: { status: "suspended" } });
    expect(await failure(endMembershipHandler(s.deps, ADMIN, { memberId: "m2", to: "resigned" }))).toBe("failed-precondition:not_active");
    expect(await failure(endMembershipHandler(s.deps, ADMIN, { memberId: "m1", to: "resigned" }))).toBe("failed-precondition:not_active");
    expect(await failure(endMembershipHandler(s.deps, ADMIN, { memberId: "m2", to: "active" }))).toBe("invalid-argument:invalid_to");
  });
});

// --------------------------------------------------------------- aidat atama

function duesSetup(members: Record<string, MemberDoc["status"]>, existing: DueAssignment[] = []) {
  const audit: AuditEntry[] = [];
  const created: DueAssignment[] = [...existing];
  const tx: DuesTx = {
    listActiveMemberIds: async () => Object.entries(members).filter(([, s]) => s === "active").map(([id]) => id),
    getMemberStatus: async (id) => members[id] ?? null,
    assignedMemberIds: async (periodId) => new Set(created.filter((d) => d.periodId === periodId).map((d) => d.memberId)),
    createDues: async (items) => void created.push(...items),
  };
  const deps = {
    dues: { run: async <T>(fn: (t: DuesTx) => Promise<T>) => fn(tx) },
    audit: { write: async (e: AuditEntry) => void audit.push(e) },
    nowMs: () => NOW,
  };
  return { deps, audit, created };
}

describe("assignDues", () => {
  const body = { periodLabel: "2026-2027", amountMinor: 120000, dueDateMs: NOW + 30 * DAY, allowPartial: true };
  const members = { m1: "active", m2: "active", m3: "suspended", m4: "pending" } as const;

  it("yalnızca finans yöneticisi", async () => {
    const s = duesSetup({ ...members });
    expect(await failure(assignDuesHandler(s.deps, ADMIN, body))).toBe("permission-denied:");
    expect(s.created).toHaveLength(0);
  });

  it("tüm aktif üyelere atar, dönem kimliği türetir, denetim kaydı yazar", async () => {
    const s = duesSetup({ ...members });
    const out = await assignDuesHandler(s.deps, FIN, body);
    expect(out).toEqual({ created: 2, skipped: 0, periodId: "per_2026-2027" });
    expect(s.created.map((d) => d.memberId).sort()).toEqual(["m1", "m2"]);
    expect(s.created[0]).toMatchObject({ amountMinor: 120000, paidMinor: 0, allowPartial: true, createdBy: "fin1", currency: "TRY" });
    expect(s.audit[0]).toMatchObject({ action: "due.create", targetId: "per_2026-2027", after: { created: 2 } });
  });

  it("aynı dönem tekrar atanamaz; yeni üye eklenince yalnızca o atanır", async () => {
    const s = duesSetup({ ...members });
    await assignDuesHandler(s.deps, FIN, body);
    expect(await failure(assignDuesHandler(s.deps, FIN, body))).toBe("already-exists:already_assigned");
    const s2 = duesSetup({ ...members, m5: "active" }, s.created);
    const out = await assignDuesHandler(s2.deps, FIN, body);
    expect(out.created).toBe(1);
    expect(out.skipped).toBe(2);
  });

  it("tek üyeye atama: aktif olmayan veya olmayan üye reddedilir", async () => {
    const s = duesSetup({ ...members });
    expect(await failure(assignDuesHandler(s.deps, FIN, { ...body, memberId: "m3" }))).toBe("failed-precondition:member_not_active");
    expect(await failure(assignDuesHandler(s.deps, FIN, { ...body, memberId: "yok" }))).toBe("not-found:member_not_found");
    const out = await assignDuesHandler(s.deps, FIN, { ...body, memberId: "m1" });
    expect(out.created).toBe(1);
  });

  it("girdi kuralları: geçmiş vade, tutar, dönem adı", async () => {
    const s = duesSetup({ ...members });
    expect(await failure(assignDuesHandler(s.deps, FIN, { ...body, dueDateMs: NOW - 1 }))).toBe("invalid-argument:due_date_in_past");
    expect(await failure(assignDuesHandler(s.deps, FIN, { ...body, amountMinor: 0 }))).toMatch(/^invalid-argument:/);
    expect(await failure(assignDuesHandler(s.deps, FIN, { ...body, amountMinor: 12.5 }))).toMatch(/^invalid-argument:/);
    expect(await failure(assignDuesHandler(s.deps, FIN, { ...body, periodLabel: "x" }))).toMatch(/^invalid-argument:/);
    expect(s.created).toHaveLength(0);
  });

  it("periodIdFor güvenli kimlik üretir", () => {
    expect(periodIdFor("2026-2027")).toBe("per_2026-2027");
    expect(periodIdFor(" Güz / 2027 ")).toBe("per_Güz_2027");
  });
});

// --------------------------------------------------------------- iade

function payment(over: Partial<PaymentDoc>): PaymentDoc {
  return {
    id: "pay1", kind: "donation", refId: "general", userId: null, amountMinor: 50000, currency: "TRY",
    status: "succeeded", provider: "simulation", providerRef: null, simulated: true, idempotencyKey: "k",
    manual: false, recordedBy: null, note: null, refundedMinor: 0, createdAtMs: NOW - DAY, updatedAtMs: NOW - DAY,
    succeededAtMs: NOW - DAY, failureCode: null, flag: null, ...over,
  };
}

function refundSetup(payments: PaymentDoc[]) {
  const audit: AuditEntry[] = [];
  const store = new Map(payments.map((p) => [p.id, p]));
  const refunds: RefundRow[] = [];
  const tx: RefundTx = {
    getPayment: async (id) => store.get(id) ?? null,
    findByIdempotencyKey: async () => null,
    findByProviderRef: async () => null,
    listPendingCreatedBefore: async () => [],
    createPayment: async () => { throw new Error("kullanılmaz"); },
    updatePayment: async (id, patch) => void store.set(id, { ...store.get(id)!, ...patch }),
    createRefund: async (r) => {
      const id = `ref${refunds.length + 1}`;
      refunds.push({ id, ...r });
      return id;
    },
  };
  const deps = {
    refunds: { run: async <T>(fn: (t: RefundTx) => Promise<T>) => fn(tx) },
    audit: { write: async (e: AuditEntry) => void audit.push(e) },
    nowMs: () => NOW,
  };
  return { deps, audit, store, refunds };
}

describe("issueRefund", () => {
  const body = { paymentId: "pay1", amountMinor: 20000, reason: "Mükerrer ödeme" };

  it("yalnızca finans yöneticisi", async () => {
    const s = refundSetup([payment({})]);
    expect(await failure(issueRefundHandler(s.deps, ADMIN, body))).toBe("permission-denied:");
    expect(s.refunds).toHaveLength(0);
  });

  it("kısmi sonra tam iade: durum, tutar, kayıt ve denetim tutarlı", async () => {
    const s = refundSetup([payment({})]);
    const a = await issueRefundHandler(s.deps, FIN, body);
    expect(a).toMatchObject({ refundId: "ref1", paymentStatus: "partially_refunded", refundedMinor: 20000 });
    const b = await issueRefundHandler(s.deps, FIN, { ...body, amountMinor: 30000 });
    expect(b).toMatchObject({ paymentStatus: "refunded", refundedMinor: 50000 });
    expect(s.store.get("pay1")).toMatchObject({ status: "refunded", refundedMinor: 50000, updatedAtMs: NOW });
    expect(s.refunds.map((r) => r.amountMinor)).toEqual([20000, 30000]);
    expect(s.refunds[0]).toMatchObject({ requestedBy: "fin1", status: "succeeded", kind: "donation" });
    expect(s.audit.map((e) => e.action)).toEqual(["refund.issue", "refund.issue"]);
    expect(s.audit[1]).toMatchObject({ before: { refundedMinor: 20000 }, after: { refundedMinor: 50000, status: "refunded" } });
  });

  it("kalanı aşan iade reddedilir ve hiçbir şey yazmaz", async () => {
    const s = refundSetup([payment({ refundedMinor: 40000, status: "partially_refunded" })]);
    expect(await failure(issueRefundHandler(s.deps, FIN, { ...body, amountMinor: 20000 }))).toBe("invalid-argument:exceeds_remaining");
    expect(s.refunds).toHaveLength(0);
    expect(s.store.get("pay1")?.refundedMinor).toBe(40000);
    expect(s.audit).toHaveLength(0);
  });

  it("iade edilemeyen durumlar, olmayan ödeme, kısa gerekçe", async () => {
    const s = refundSetup([payment({ id: "p2", status: "pending" }), payment({ id: "p3", status: "failed" }), payment({})]);
    expect(await failure(issueRefundHandler(s.deps, FIN, { ...body, paymentId: "p2" }))).toBe("failed-precondition:not_refundable");
    expect(await failure(issueRefundHandler(s.deps, FIN, { ...body, paymentId: "p3" }))).toBe("failed-precondition:not_refundable");
    expect(await failure(issueRefundHandler(s.deps, FIN, { ...body, paymentId: "yok" }))).toBe("not-found:payment_not_found");
    expect(await failure(issueRefundHandler(s.deps, FIN, { ...body, reason: "abc" }))).toMatch(/^invalid-argument:/);
    expect(await failure(issueRefundHandler(s.deps, FIN, { ...body, amountMinor: 0 }))).toMatch(/^invalid-argument:/);
  });

  it("gerçek sağlayıcı ödemesi para iadesi desteklenene kadar reddedilir", async () => {
    const s = refundSetup([payment({ simulated: false, manual: false, provider: "iyzico" })]);
    expect(await failure(issueRefundHandler(s.deps, FIN, body))).toBe("failed-precondition:provider_refund_unavailable");
    expect(s.store.get("pay1")?.refundedMinor).toBe(0);
    expect(s.refunds).toHaveLength(0);
  });

  it("manuel ödeme iade edilebilir", async () => {
    const s = refundSetup([payment({ simulated: false, manual: true, provider: "manual" })]);
    expect((await issueRefundHandler(s.deps, FIN, body)).refundedMinor).toBe(20000);
  });
});

// --------------------------------------------------------------- dışa aktarma

describe("exportReport", () => {
  const payRow = (over: Partial<ExportPaymentRow> = {}): ExportPaymentRow => ({
    id: "pay1", kind: "donation", refId: "general", amountMinor: 125050, currency: "TRY", status: "succeeded",
    provider: "simulation", manual: false, simulated: true, refundedMinor: 0, createdAtMs: NOW, succeededAtMs: NOW, ...over,
  });

  function exportSetup(rows: ExportPaymentRow[], refunds: RefundRow[] = [], maxRows?: number) {
    const audit: AuditEntry[] = [];
    const ranges: unknown[] = [];
    const deps = {
      reader: {
        payments: async (range: unknown, limit: number) => (ranges.push(range), rows.slice(0, limit)),
        dues: async () => [],
        refunds: async (_r: unknown, limit: number) => refunds.slice(0, limit),
      },
      audit: { write: async (e: AuditEntry) => void audit.push(e) },
      nowMs: () => NOW,
      ...(maxRows === undefined ? {} : { maxRows }),
    };
    return { deps, audit, ranges };
  }

  it("yalnızca finans yöneticisi (sistem yöneticisi bile dışa aktaramaz)", async () => {
    const s = exportSetup([payRow()]);
    expect(await failure(exportReportHandler(s.deps, ADMIN, { kind: "payments" }))).toBe("permission-denied:");
    expect(s.audit).toHaveLength(0);
  });

  it("CSV: BOM, noktalı virgül, CRLF, kuruş ve biçimli tutar; denetim kaydı", async () => {
    const s = exportSetup([payRow(), payRow({ id: "pay2", manual: true, simulated: false, succeededAtMs: null })]);
    const out = await exportReportHandler(s.deps, FIN, { kind: "payments" });
    expect(out.rows).toBe(2);
    const lines = out.csv.split("\r\n");
    expect(out.csv.startsWith("﻿odeme_id;tur;")).toBe(true);
    expect(lines[1]).toContain("pay1;donation;general;125050;1.250,50 ₺;TRY;succeeded;simulation;hayir;evet;0;");
    expect(lines[2]).toContain("pay2;");
    expect(lines[2]?.endsWith(";")).toBe(true); // başarı zamanı boş
    expect(lines).toHaveLength(4); // başlık + 2 satır + sondaki boş
    expect(s.audit[0]).toMatchObject({ action: "export.financial", targetId: "payments", after: { rows: 2 } });
  });

  it("formül enjeksiyonu etkisizleşir (iade gerekçesi)", async () => {
    const r: RefundRow = { id: "r1", paymentId: "pay1", kind: "donation", amountMinor: 100, currency: "TRY", status: "succeeded", reason: "=HYPERLINK(\"x\")", requestedBy: "fin1", createdAtMs: NOW };
    const s = exportSetup([], [r]);
    const out = await exportReportHandler(s.deps, FIN, { kind: "refunds" });
    expect(out.csv).toContain("\"'=HYPERLINK(\"\"x\"\")\"");
    expect(out.csv).not.toContain(";=HYPERLINK");
  });

  it("tarih aralığı okuyucuya iletilir; ters aralık reddedilir", async () => {
    const s = exportSetup([payRow()]);
    await exportReportHandler(s.deps, FIN, { kind: "payments", fromMs: 10, toMs: 20 });
    expect(s.ranges[0]).toEqual({ fromMs: 10, toMs: 20 });
    expect(await failure(exportReportHandler(s.deps, FIN, { kind: "payments", fromMs: 30, toMs: 20 }))).toBe("invalid-argument:invalid_range");
    expect(await failure(exportReportHandler(s.deps, FIN, { kind: "bilinmeyen" }))).toBe("invalid-argument:invalid_kind");
  });

  it("satır sınırı aşılırsa dışa aktarma reddedilir ve denetim yazılmaz", async () => {
    const s = exportSetup([payRow({ id: "a" }), payRow({ id: "b" }), payRow({ id: "c" })], [], 2);
    expect(await failure(exportReportHandler(s.deps, FIN, { kind: "payments" }))).toBe("failed-precondition:too_many_rows");
    expect(s.audit).toHaveLength(0);
  });
});
