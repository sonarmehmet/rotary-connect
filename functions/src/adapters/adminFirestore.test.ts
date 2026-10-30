import { describe, expect, it } from "vitest";
import { assignDuesHandler, assignRoleHandler, approveMembershipHandler, endMembershipHandler, exportReportHandler, issueRefundHandler } from "../handlers/adminOps";
import { Role } from "../lib/roles";
import { FakeFirestore, fakeClock } from "../testing/fakeFirestore";
import {
  AuthRolePort, FirestoreAdminTxRunner, FirestoreAuditSink, FirestoreDuesTxRunner,
  FirestoreExportReader, FirestoreRefundTxRunner,
} from "./adminFirestore";

const NOW = 1_800_000_000_000;
const DAY = 86_400_000;
const sysAdmin = { uid: "admin1", token: { role: "system_admin" } };
const finance = { uid: "fin1", token: { role: "finance_manager" } };

class FakeAuth implements AuthRolePort {
  roles = new Map<string, Role>([["u1", "registered_user"], ["admin1", "system_admin"]]);
  async getRole(id: string) { return this.roles.get(id) ?? null; }
  async setRole(id: string, r: Role) { this.roles.set(id, r); }
  async countWithRole(r: Role) { return [...this.roles.values()].filter((x) => x === r).length; }
}

function setup() {
  const db = new FakeFirestore();
  const auth = new FakeAuth();
  db.seed("club_members", "m1", {
    userId: "u1", memberNo: null, status: "pending", requestedAt: fakeClock.fromMs(NOW - DAY),
    joinedAt: null, approvedBy: null,
  });
  const audit = new FirestoreAuditSink(db, fakeClock);
  const admin = { store: new FirestoreAdminTxRunner(db, fakeClock, auth), audit, nowMs: () => NOW };
  return { db, auth, audit, admin };
}

describe("Firestore adaptörü — yönetim işlemleri", () => {
  it("üyelik onayı: belge alanları, claim ve denetim kaydı", async () => {
    const { db, auth, admin } = setup();
    const r = await approveMembershipHandler(admin, sysAdmin, { memberId: "m1", memberNo: "123" });
    expect(r.role).toBe("club_member");
    const m = db.raw("club_members")[0]?.data ?? {};
    expect(m.status).toBe("active");
    expect(m.memberNo).toBe("123");
    expect(m.joinedAt).toEqual({ __ts: NOW });
    expect(m.approvedBy).toBe("admin1");
    expect(Object.keys(m).some((k) => k.endsWith("Ms"))).toBe(false);
    expect(auth.roles.get("u1")).toBe("club_member");
    expect(db.raw("audit_logs")[0]?.data.action).toBe("membership.approve");
    expect(db.raw("audit_logs")[0]?.data.createdAt).toEqual({ __ts: NOW });
  });

  it("aynı üye numarası ikinci üyeye verilmez ve claim değişmez", async () => {
    const { db, auth, admin } = setup();
    db.seed("club_members", "m2", { userId: "u2", memberNo: "123", status: "active", requestedAt: fakeClock.fromMs(NOW) });
    auth.roles.set("u2", "club_member");
    await expect(approveMembershipHandler(admin, sysAdmin, { memberId: "m1", memberNo: "123" }))
      .rejects.toMatchObject({ reason: "member_no_taken" });
    expect(auth.roles.get("u1")).toBe("registered_user");
    expect(db.raw("club_members").find((x) => x.id === "m1")?.data.status).toBe("pending");
  });

  it("üyelik sonlandırma claim'i düşürür", async () => {
    const { auth, admin } = setup();
    await approveMembershipHandler(admin, sysAdmin, { memberId: "m1", memberNo: "7" });
    await endMembershipHandler(admin, sysAdmin, { memberId: "m1", to: "resigned" });
    expect(auth.roles.get("u1")).toBe("registered_user");
  });

  it("rol atama claim yazar; son yönetici düşürülemez", async () => {
    const { auth, admin } = setup();
    await assignRoleHandler(admin, sysAdmin, { userId: "u1", role: "content_manager" });
    expect(auth.roles.get("u1")).toBe("content_manager");
    auth.roles.delete("u1");
    await expect(assignRoleHandler(admin, sysAdmin, { userId: "admin1", role: "registered_user" }))
      .rejects.toMatchObject({ reason: "last_admin" });
  });

  it("toplu aidat: borç belgesi userId ve doğru alanlarla yazılır; ikinci çağrı atlar", async () => {
    const { db, audit } = setup();
    const deps = { dues: new FirestoreDuesTxRunner(db, fakeClock), audit, nowMs: () => NOW };
    db.seed("club_members", "m1", { userId: "u1", memberNo: "1", status: "active", requestedAt: fakeClock.fromMs(NOW) });
    const body = { periodLabel: "2026-2027", amountMinor: 120_000, dueDateMs: NOW + 30 * DAY, allowPartial: true };
    const first = await assignDuesHandler(deps, finance, body);
    expect(first).toMatchObject({ created: 1, skipped: 0, periodId: "per_2026-2027" });
    const due = db.raw("membership_dues")[0]?.data ?? {};
    expect(due).toMatchObject({
      userId: "u1", memberId: "m1", periodId: "per_2026-2027", amountMinor: 120_000, paidMinor: 0,
      status: "unpaid", allowPartial: true, createdBy: "fin1",
    });
    expect(due.dueDate).toEqual({ __ts: NOW + 30 * DAY });
    await expect(assignDuesHandler(deps, finance, body)).rejects.toMatchObject({ reason: "already_assigned" });
    expect(db.raw("membership_dues").length).toBe(1);
  });

  it("iade: refunds belgesi yazılır, ödeme güncellenir", async () => {
    const { db, audit } = setup();
    db.seed("payments", "p1", {
      kind: "donation", refId: "c1", userId: "u1", amountMinor: 50_000, currency: "TRY", status: "succeeded",
      provider: "simulation", providerRef: "r1", simulated: true, idempotencyKey: "k", manual: false,
      recordedBy: null, note: null, refundedMinor: 0, createdAt: fakeClock.fromMs(NOW - DAY),
      updatedAt: fakeClock.fromMs(NOW - DAY), succeededAt: fakeClock.fromMs(NOW - DAY), failureCode: null, flag: null,
    });
    const deps = { refunds: new FirestoreRefundTxRunner(db, fakeClock), audit, nowMs: () => NOW };
    const r = await issueRefundHandler(deps, finance, { paymentId: "p1", amountMinor: 20_000, reason: "yanlış tutar" });
    expect(r.paymentStatus).toBe("partially_refunded");
    const rf = db.raw("refunds")[0]?.data ?? {};
    expect(rf).toMatchObject({ paymentId: "p1", amountMinor: 20_000, requestedBy: "fin1", kind: "donation" });
    expect(rf.createdAt).toEqual({ __ts: NOW });
    expect(db.raw("payments")[0]?.data.refundedMinor).toBe(20_000);
  });

  it("CSV dışa aktarma tarih aralığıyla süzer ve denetim yazar", async () => {
    const { db, audit } = setup();
    const row = (t: number) => ({
      kind: "donation", refId: "c1", userId: "u1", amountMinor: 10_000, currency: "TRY", status: "succeeded",
      provider: "simulation", providerRef: null, simulated: true, idempotencyKey: `k${t}`, manual: false,
      recordedBy: null, note: null, refundedMinor: 0, createdAt: fakeClock.fromMs(t),
      updatedAt: fakeClock.fromMs(t), succeededAt: fakeClock.fromMs(t), failureCode: null, flag: null,
    });
    db.seed("payments", "a", row(NOW - 10 * DAY));
    db.seed("payments", "b", row(NOW - DAY));
    const deps = { reader: new FirestoreExportReader(db, fakeClock), audit, nowMs: () => NOW };
    const out = await exportReportHandler(deps, finance, { kind: "payments", fromMs: NOW - 2 * DAY, toMs: NOW });
    expect(out.rows).toBe(1);
    expect(out.csv).toContain("b");
    expect(out.csv).not.toContain(";a;");
    expect(db.raw("audit_logs").some((l) => l.data.action === "export.financial")).toBe(true);
  });
});
