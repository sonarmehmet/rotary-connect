import { AuditEntry, buildAuditEntry } from "../audit/audit";
import { DueAssignment, MemberDoc, approveMembership, assignDues, endMembership } from "../members/members";
import { DomainError } from "../lib/errors";
import { buildCsv, formatMoney } from "../lib/csv";
import { Role, requireRole } from "../lib/roles";
import { planRefund } from "../payments/refunds";
import { PaymentKindWire, PaymentTx, PaymentDoc } from "../payments/repo";
import { AuditSink, CallableAuth, requireAuth } from "./handlers";
import { asBool, asEnum, asInt, asObject, asOptionalString, asString } from "./validate";

/**
 * Yönetim paneli işleyicileri: rol atama, üyelik onayı/sonlandırma, toplu aidat atama, iade ve
 * CSV dışa aktarma. SDK'dan bağımsızdır; Firestore/Auth uygulaması portları doldurur.
 * İlke (diğer işleyicilerle aynı): yetki ÖNCE, sonra girdi doğrulama, sonra iş kuralı;
 * her kritik işlem denetim kaydı yazar (kişisel veri yok).
 */

// ------------------------------------------------------------------ ortak portlar

/** Üyelik ve rol işlemleri için transaction içi erişim. */
export interface AdminTx {
  getMember(memberId: string): Promise<MemberDoc | null>;
  /** `exceptMemberId` dışında bu üye numarasını taşıyan kayıt var mı? */
  memberNoTaken(memberNo: string, exceptMemberId: string): Promise<boolean>;
  saveMember(memberId: string, doc: MemberDoc): Promise<void>;
  /** `null` = kullanıcı yok. Claim yoksa `registered_user` dönmelidir. */
  getUserRole(userId: string): Promise<Role | null>;
  /** Auth custom claim'ini yazar (uygulama Admin SDK `setCustomUserClaims` kullanır). */
  setUserRole(userId: string, role: Role): Promise<void>;
  countUsersWithRole(role: Role): Promise<number>;
}

export interface AdminTxRunner {
  run<T>(fn: (tx: AdminTx) => Promise<T>): Promise<T>;
}

export interface AdminOpsDeps {
  readonly store: AdminTxRunner;
  readonly audit: AuditSink;
  readonly nowMs: () => number;
}

async function writeAudit(
  deps: { audit: AuditSink },
  entry: Omit<AuditEntry, "createdAtMs"> & { nowMs: number },
): Promise<void> {
  const { nowMs, ...rest } = entry;
  await deps.audit.write(buildAuditEntry({ ...rest, nowMs }));
}

// ------------------------------------------------------------------ rol atama

/** `club_member` elle atanmaz: yalnızca üyelik onayıyla gelir. */
export const ASSIGNABLE_ROLES = ["registered_user", "content_manager", "finance_manager", "system_admin"] as const;

export async function assignRoleHandler(
  deps: AdminOpsDeps,
  auth: CallableAuth | null | undefined,
  data: unknown,
): Promise<{ userId: string; role: Role }> {
  const ctx = requireAuth(auth);
  requireRole(ctx.role, ["system_admin"]);
  const o = asObject(data, "data");
  const userId = asString(o["userId"], "userId", { max: 128 });
  const role = asEnum(o["role"], "role", ASSIGNABLE_ROLES);
  const nowMs = deps.nowMs();

  const before = await deps.store.run(async (tx) => {
    const current = await tx.getUserRole(userId);
    if (current === null) throw new DomainError("not-found", "Kullanıcı bulunamadı", "user_not_found");
    if (current === role) {
      throw new DomainError("failed-precondition", "Kullanıcı zaten bu role sahip", "same_role");
    }
    if (current === "club_member" && role === "registered_user") {
      // Rol düşerse üyelik kaydı aktif kalıp claim'siz tutarsızlık oluşurdu.
      throw new DomainError("failed-precondition", "Üyeliği sonlandırmak için üyelik ekranını kullanın", "use_membership_flow");
    }
    if (current === "system_admin") {
      // Panel kilitlenmesin: son sistem yöneticisi düşürülemez.
      if ((await tx.countUsersWithRole("system_admin")) <= 1) {
        throw new DomainError("failed-precondition", "Son sistem yöneticisinin rolü değiştirilemez", "last_admin");
      }
    }
    await tx.setUserRole(userId, role);
    return current;
  });

  await writeAudit(deps, {
    actorId: ctx.uid,
    actorRole: ctx.role,
    action: "role.assign",
    targetType: "user",
    targetId: userId,
    before: { role: before },
    after: { role },
    nowMs,
  });
  return { userId, role };
}

// ------------------------------------------------------------------ üyelik

export async function approveMembershipHandler(
  deps: AdminOpsDeps,
  auth: CallableAuth | null | undefined,
  data: unknown,
): Promise<{ memberId: string; memberNo: string; role: Role }> {
  const ctx = requireAuth(auth);
  requireRole(ctx.role, ["system_admin"]);
  const o = asObject(data, "data");
  const memberId = asString(o["memberId"], "memberId", { max: 128 });
  const memberNo = asString(o["memberNo"], "memberNo", { max: 30 });
  const nowMs = deps.nowMs();

  const out = await deps.store.run(async (tx) => {
    const member = await tx.getMember(memberId);
    if (!member) throw new DomainError("not-found", "Üyelik kaydı bulunamadı", "member_not_found");
    const currentRole = await tx.getUserRole(member.userId);
    if (currentRole === null) throw new DomainError("not-found", "Kullanıcı bulunamadı", "user_not_found");
    const result = approveMembership(ctx.role, ctx.uid, member, currentRole, memberNo, nowMs);
    if (await tx.memberNoTaken(result.member.memberNo ?? memberNo, memberId)) {
      throw new DomainError("already-exists", "Bu üye numarası zaten kullanılıyor", "member_no_taken");
    }
    await tx.saveMember(memberId, result.member);
    if (result.newRole !== currentRole) await tx.setUserRole(member.userId, result.newRole);
    return { memberNo: result.member.memberNo ?? memberNo, role: result.newRole, from: member.status };
  });

  await writeAudit(deps, {
    actorId: ctx.uid,
    actorRole: ctx.role,
    action: "membership.approve",
    targetType: "club_member",
    targetId: memberId,
    before: { status: out.from },
    after: { status: "active" },
    nowMs,
  });
  return { memberId, memberNo: out.memberNo, role: out.role };
}

export async function endMembershipHandler(
  deps: AdminOpsDeps,
  auth: CallableAuth | null | undefined,
  data: unknown,
): Promise<{ memberId: string; status: "suspended" | "resigned"; role: Role }> {
  const ctx = requireAuth(auth);
  requireRole(ctx.role, ["system_admin"]);
  const o = asObject(data, "data");
  const memberId = asString(o["memberId"], "memberId", { max: 128 });
  const to = asEnum(o["to"], "to", ["suspended", "resigned"] as const);
  const nowMs = deps.nowMs();

  const out = await deps.store.run(async (tx) => {
    const member = await tx.getMember(memberId);
    if (!member) throw new DomainError("not-found", "Üyelik kaydı bulunamadı", "member_not_found");
    const currentRole = await tx.getUserRole(member.userId);
    if (currentRole === null) throw new DomainError("not-found", "Kullanıcı bulunamadı", "user_not_found");
    const result = endMembership(ctx.role, member, to, currentRole);
    await tx.saveMember(memberId, result.member);
    if (result.newRole !== currentRole) await tx.setUserRole(member.userId, result.newRole);
    return result.newRole;
  });

  await writeAudit(deps, {
    actorId: ctx.uid,
    actorRole: ctx.role,
    action: "membership.end",
    targetType: "club_member",
    targetId: memberId,
    before: { status: "active" },
    after: { status: to },
    nowMs,
  });
  return { memberId, status: to, role: out };
}

// ------------------------------------------------------------------ toplu aidat

export interface DuesTx {
  /** Aktif üyelerin `club_members` kimlikleri. */
  listActiveMemberIds(): Promise<string[]>;
  /** `null` = üye yok. */
  getMemberStatus(memberId: string): Promise<MemberDoc["status"] | null>;
  assignedMemberIds(periodId: string): Promise<Set<string>>;
  createDues(items: readonly DueAssignment[]): Promise<void>;
}

export interface DuesTxRunner {
  run<T>(fn: (tx: DuesTx) => Promise<T>): Promise<T>;
}

export interface DuesHandlerDeps {
  readonly dues: DuesTxRunner;
  readonly audit: AuditSink;
  readonly nowMs: () => number;
}

/** "2026-2027" → "per_2026-2027". Harf/rakam/tire dışı karakterler `_` olur. */
export function periodIdFor(label: string): string {
  return `per_${label.trim().replace(/[^\p{L}\p{N}-]+/gu, "_")}`;
}

export async function assignDuesHandler(
  deps: DuesHandlerDeps,
  auth: CallableAuth | null | undefined,
  data: unknown,
): Promise<{ created: number; skipped: number; periodId: string }> {
  const ctx = requireAuth(auth);
  requireRole(ctx.role, ["finance_manager"]);
  const o = asObject(data, "data");
  const periodLabel = asString(o["periodLabel"], "periodLabel", { min: 3, max: 40 });
  const amountMinor = asInt(o["amountMinor"], "amountMinor", { min: 1, max: 1_000_000_000 });
  const dueDateMs = asInt(o["dueDateMs"], "dueDateMs", { min: 0, max: Number.MAX_SAFE_INTEGER });
  const allowPartial = asBool(o["allowPartial"], "allowPartial");
  const memberId = asOptionalString(o["memberId"], "memberId", { max: 128 });
  const nowMs = deps.nowMs();
  const periodId = periodIdFor(periodLabel);

  const result = await deps.dues.run(async (tx) => {
    let targets: string[];
    if (memberId === undefined) {
      targets = await tx.listActiveMemberIds();
    } else {
      const status = await tx.getMemberStatus(memberId);
      if (status === null) throw new DomainError("not-found", "Üyelik kaydı bulunamadı", "member_not_found");
      if (status !== "active") {
        throw new DomainError("failed-precondition", "Yalnızca aktif üyelere aidat atanır", "member_not_active");
      }
      targets = [memberId];
    }
    const plan = assignDues({
      actorRole: ctx.role,
      actorId: ctx.uid,
      periodId,
      periodLabel,
      amountMinor,
      currency: "TRY",
      dueDateMs,
      allowPartial,
      nowMs,
      activeMemberIds: targets,
      alreadyAssignedMemberIds: await tx.assignedMemberIds(periodId),
    });
    if (plan.created.length === 0) {
      throw new DomainError("already-exists", "Bu dönem için borçlar zaten atanmış", "already_assigned");
    }
    await tx.createDues(plan.created);
    return plan;
  });

  await writeAudit(deps, {
    actorId: ctx.uid,
    actorRole: ctx.role,
    action: "due.create",
    targetType: "due_period",
    targetId: periodId,
    before: null,
    after: { periodLabel, amountMinor, created: result.created.length },
    nowMs,
  });
  return { created: result.created.length, skipped: result.skipped.length, periodId };
}

// ------------------------------------------------------------------ iade

export interface RefundRow {
  readonly id: string;
  readonly paymentId: string;
  readonly kind: PaymentKindWire;
  readonly amountMinor: number;
  readonly currency: string;
  readonly status: "pending" | "succeeded" | "failed";
  readonly reason: string;
  readonly requestedBy: string;
  readonly createdAtMs: number;
}

export interface RefundTx extends PaymentTx {
  createRefund(r: Omit<RefundRow, "id">): Promise<string>;
}

export interface RefundTxRunner {
  run<T>(fn: (tx: RefundTx) => Promise<T>): Promise<T>;
}

export interface RefundHandlerDeps {
  readonly refunds: RefundTxRunner;
  /**
   * Gerçek sağlayıcı ödemesinde para iadesini sağlayıcıda yapar (ağ çağrısı, transaction DIŞINDA).
   * `idempotencyKey` aynı iade için aynıdır: sağlayıcıya tekrar çağrı çift iade üretmemelidir.
   * Verilmezse yalnızca simülasyon/manuel ödemeler iade edilebilir.
   */
  readonly providerRefund?: (payment: PaymentDoc, amountMinor: number, idempotencyKey: string) => Promise<void>;
  readonly audit: AuditSink;
  readonly nowMs: () => number;
}

export async function issueRefundHandler(
  deps: RefundHandlerDeps,
  auth: CallableAuth | null | undefined,
  data: unknown,
): Promise<{ refundId: string; paymentStatus: string; refundedMinor: number }> {
  const ctx = requireAuth(auth);
  requireRole(ctx.role, ["finance_manager"]);
  const o = asObject(data, "data");
  const paymentId = asString(o["paymentId"], "paymentId", { max: 128 });
  const amountMinor = asInt(o["amountMinor"], "amountMinor", { min: 1, max: 1_000_000_000 });
  const reason = asString(o["reason"], "reason", { min: 5, max: 300 });
  const nowMs = deps.nowMs();

  // 1) Planla (yalnızca okuma): geçersiz/aşan iade sağlayıcıya HİÇ gitmez.
  const first = await deps.refunds.run(async (tx) => {
    const p = await tx.getPayment(paymentId);
    if (!p) throw new DomainError("not-found", "Ödeme bulunamadı", "payment_not_found");
    const plan = planRefund(p, amountMinor);
    if (!p.simulated && !p.manual && !deps.providerRefund) {
      throw new DomainError("failed-precondition", "Sağlayıcı iadesi henüz desteklenmiyor", "provider_refund_unavailable");
    }
    return { p, plan };
  });

  // 2) Gerçek sağlayıcıda parayı iade et. Anahtar (ödeme + önceki iade + tutar) aynı iade için sabittir:
  //    adım 3 başarısız olup yönetici tekrar denerse sağlayıcıda çift iade oluşmaz.
  if (!first.p.simulated && !first.p.manual && deps.providerRefund) {
    try {
      await deps.providerRefund(first.p, first.plan.refundMinor, `refund_${paymentId}_${first.p.refundedMinor}_${first.plan.refundMinor}`);
    } catch {
      throw new DomainError("unavailable", "Sağlayıcı iadeyi işleyemedi; kayıt değiştirilmedi", "provider_refund_failed");
    }
  }

  // 3) Kaydı yaz (taze okumayla yeniden planla: arada başka iade olduysa tutarlılık korunur).
  const out = await deps.refunds.run(async (tx) => {
    const p = await tx.getPayment(paymentId);
    if (!p) throw new DomainError("not-found", "Ödeme bulunamadı", "payment_not_found");
    const plan = planRefund(p, amountMinor);
    await tx.updatePayment(paymentId, {
      refundedMinor: plan.newRefundedMinor,
      status: plan.nextStatus,
      updatedAtMs: nowMs,
    });
    const refundId = await tx.createRefund({
      paymentId,
      kind: p.kind,
      amountMinor: plan.refundMinor,
      currency: p.currency,
      status: "succeeded",
      reason,
      requestedBy: ctx.uid,
      createdAtMs: nowMs,
    });
    return { refundId, plan, previous: p.refundedMinor };
  });

  await writeAudit(deps, {
    actorId: ctx.uid,
    actorRole: ctx.role,
    action: "refund.issue",
    targetType: "payment",
    targetId: paymentId,
    before: { refundedMinor: out.previous },
    after: { refundedMinor: out.plan.newRefundedMinor, status: out.plan.nextStatus },
    nowMs,
  });
  return { refundId: out.refundId, paymentStatus: out.plan.nextStatus, refundedMinor: out.plan.newRefundedMinor };
}

// ------------------------------------------------------------------ CSV dışa aktarma

export interface ExportPaymentRow {
  readonly id: string;
  readonly kind: PaymentKindWire;
  readonly refId: string;
  readonly amountMinor: number;
  readonly currency: string;
  readonly status: string;
  readonly provider: string;
  readonly manual: boolean;
  readonly simulated: boolean;
  readonly refundedMinor: number;
  readonly createdAtMs: number;
  readonly succeededAtMs: number | null;
}

export interface ExportDueRow {
  readonly id: string;
  readonly memberId: string;
  readonly periodLabel: string;
  readonly amountMinor: number;
  readonly paidMinor: number;
  readonly currency: string;
  readonly dueDateMs: number;
  readonly status: string;
  readonly allowPartial: boolean;
}

export interface ExportRange {
  readonly fromMs: number | null;
  readonly toMs: number | null;
}

export interface ExportReader {
  /** En çok `limit` satır döner; sınır aşılırsa `limit` satır döner ve çağıran reddeder. */
  payments(range: ExportRange, limit: number): Promise<ExportPaymentRow[]>;
  dues(range: ExportRange, limit: number): Promise<ExportDueRow[]>;
  refunds(range: ExportRange, limit: number): Promise<RefundRow[]>;
}

export interface ExportDeps {
  readonly reader: ExportReader;
  readonly audit: AuditSink;
  readonly nowMs: () => number;
  readonly maxRows?: number;
}

export const EXPORT_MAX_ROWS = 50_000;
const iso = (ms: number): string => new Date(ms).toISOString();
const yn = (b: boolean): string => (b ? "evet" : "hayir");

export async function exportReportHandler(
  deps: ExportDeps,
  auth: CallableAuth | null | undefined,
  data: unknown,
): Promise<{ csv: string; rows: number }> {
  const ctx = requireAuth(auth);
  requireRole(ctx.role, ["finance_manager"]);
  const o = asObject(data, "data");
  const kind = asEnum(o["kind"], "kind", ["payments", "dues", "refunds"] as const);
  const fromMs = o["fromMs"] === undefined || o["fromMs"] === null ? null : asInt(o["fromMs"], "fromMs", { min: 0, max: Number.MAX_SAFE_INTEGER });
  const toMs = o["toMs"] === undefined || o["toMs"] === null ? null : asInt(o["toMs"], "toMs", { min: 0, max: Number.MAX_SAFE_INTEGER });
  if (fromMs !== null && toMs !== null && fromMs > toMs) {
    throw new DomainError("invalid-argument", "Başlangıç tarihi bitişten sonra olamaz", "invalid_range");
  }
  const range: ExportRange = { fromMs, toMs };
  const max = deps.maxRows ?? EXPORT_MAX_ROWS;
  const nowMs = deps.nowMs();

  let csv: string;
  let rows: number;
  if (kind === "payments") {
    const list = await deps.reader.payments(range, max + 1);
    rows = list.length;
    if (rows > max) throw tooMany();
    csv = buildCsv(
      ["odeme_id", "tur", "bagli_kayit", "tutar_kurus", "tutar", "para_birimi", "durum", "saglayici", "manuel", "simulasyon", "iade_kurus", "olusturma", "basari_zamani"],
      list.map((p) => [
        p.id, p.kind, p.refId, String(p.amountMinor), formatMoney(p.amountMinor, p.currency), p.currency,
        p.status, p.provider, yn(p.manual), yn(p.simulated), String(p.refundedMinor), iso(p.createdAtMs),
        p.succeededAtMs === null ? "" : iso(p.succeededAtMs),
      ]),
    );
  } else if (kind === "dues") {
    const list = await deps.reader.dues(range, max + 1);
    rows = list.length;
    if (rows > max) throw tooMany();
    csv = buildCsv(
      ["borc_id", "uye_id", "donem", "tutar_kurus", "odenen_kurus", "kalan_kurus", "para_birimi", "vade", "durum", "kismi_odeme"],
      list.map((d) => [
        d.id, d.memberId, d.periodLabel, String(d.amountMinor), String(d.paidMinor),
        String(Math.max(0, d.amountMinor - d.paidMinor)), d.currency, iso(d.dueDateMs), d.status, yn(d.allowPartial),
      ]),
    );
  } else {
    const list = await deps.reader.refunds(range, max + 1);
    rows = list.length;
    if (rows > max) throw tooMany();
    csv = buildCsv(
      ["iade_id", "odeme_id", "tur", "tutar_kurus", "tutar", "para_birimi", "durum", "gerekce", "olusturma"],
      list.map((r) => [
        r.id, r.paymentId, r.kind, String(r.amountMinor), formatMoney(r.amountMinor, r.currency), r.currency,
        r.status, r.reason, iso(r.createdAtMs),
      ]),
    );
  }

  await writeAudit(deps, {
    actorId: ctx.uid,
    actorRole: ctx.role,
    action: "export.financial",
    targetType: "report",
    targetId: kind,
    before: null,
    after: { rows, from: fromMs, to: toMs },
    nowMs,
  });
  return { csv, rows };
}

function tooMany(): DomainError {
  return new DomainError("failed-precondition", "Çok fazla satır: tarih aralığını daraltın", "too_many_rows");
}
