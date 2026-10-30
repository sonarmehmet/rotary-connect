import { DomainError } from "../lib/errors";
import { Role, parseRole, requireRole } from "../lib/roles";
import { DueDoc } from "../dues/dues";

export type MemberStatus = "pending" | "active" | "suspended" | "resigned";

export interface MemberDoc {
  readonly userId: string;
  readonly memberNo: string | null;
  readonly status: MemberStatus;
  readonly requestedAtMs: number;
  readonly joinedAtMs: number | null;
  readonly approvedBy: string | null;
}

/** Kullanıcı üyelik talebi açar. Talep ≠ üyelik: onaya kadar `club_member` yetkisi yoktur. */
export function requestMembership(existing: MemberDoc | null, userId: string, nowMs: number): MemberDoc {
  if (existing && (existing.status === "pending" || existing.status === "active")) {
    throw new DomainError("already-exists", "Üyelik talebiniz zaten var", "already_requested");
  }
  return { userId, memberNo: null, status: "pending", requestedAtMs: nowMs, joinedAtMs: null, approvedBy: null };
}

export interface ApprovalResult {
  readonly member: MemberDoc;
  /** Auth custom claim olarak yazılacak rol. */
  readonly newRole: Role;
}

/**
 * Yalnızca sistem yöneticisi onaylar. Mevcut yönetici rolü (içerik/finans) DÜŞÜRÜLMEZ:
 * yönetici aynı zamanda üye olabilir, ancak claim tek rol taşıdığı için yönetici rolü korunur.
 */
export function approveMembership(
  actorRole: unknown,
  actorId: string,
  member: MemberDoc,
  currentRole: unknown,
  memberNo: string,
  nowMs: number,
): ApprovalResult {
  requireRole(actorRole, ["system_admin"]);
  if (member.status !== "pending") {
    throw new DomainError("failed-precondition", "Yalnızca bekleyen talepler onaylanabilir", "not_pending");
  }
  if (memberNo.trim().length === 0) {
    throw new DomainError("invalid-argument", "Üye numarası gerekli", "member_no_required");
  }
  const current = parseRole(currentRole);
  const staff: readonly Role[] = ["content_manager", "finance_manager", "system_admin"];
  return {
    member: { ...member, status: "active", memberNo: memberNo.trim(), joinedAtMs: nowMs, approvedBy: actorId },
    newRole: staff.includes(current) ? current : "club_member",
  };
}

/** Askıya alma/istifa: üyelik biter, claim `registered_user`'a düşer (yönetici rolü korunur). */
export function endMembership(
  actorRole: unknown,
  member: MemberDoc,
  to: "suspended" | "resigned",
  currentRole: unknown,
): ApprovalResult {
  requireRole(actorRole, ["system_admin"]);
  if (member.status !== "active") {
    throw new DomainError("failed-precondition", "Yalnızca aktif üyelik sonlandırılabilir", "not_active");
  }
  const current = parseRole(currentRole);
  const staff: readonly Role[] = ["content_manager", "finance_manager", "system_admin"];
  return { member: { ...member, status: to }, newRole: staff.includes(current) ? current : "registered_user" };
}

export interface AssignDuesInput {
  readonly actorRole: unknown;
  readonly actorId: string;
  readonly periodId: string;
  readonly periodLabel: string;
  readonly amountMinor: number;
  readonly currency: string;
  readonly dueDateMs: number;
  readonly allowPartial: boolean;
  readonly nowMs: number;
  readonly activeMemberIds: readonly string[];
  /** Bu dönem için zaten borcu olan üyeler (mükerrer atamayı önler). */
  readonly alreadyAssignedMemberIds: ReadonlySet<string>;
}

export interface DueAssignment extends DueDoc {
  readonly memberId: string;
  readonly periodId: string;
  readonly periodLabel: string;
  readonly currency: string;
  readonly createdBy: string;
  readonly createdAtMs: number;
}

/** Toplu aidat atama: yalnızca finans yöneticisi; aynı dönem için üyeye ikinci borç oluşmaz. */
export function assignDues(i: AssignDuesInput): { created: DueAssignment[]; skipped: string[] } {
  requireRole(i.actorRole, ["finance_manager"]);
  if (!Number.isSafeInteger(i.amountMinor) || i.amountMinor <= 0) {
    throw new DomainError("invalid-argument", "Aidat tutarı geçersiz", "invalid_amount");
  }
  if (i.dueDateMs <= i.nowMs) {
    throw new DomainError("invalid-argument", "Son ödeme tarihi gelecekte olmalı", "due_date_in_past");
  }
  const created: DueAssignment[] = [];
  const skipped: string[] = [];
  const seen = new Set<string>();
  for (const memberId of i.activeMemberIds) {
    if (seen.has(memberId) || i.alreadyAssignedMemberIds.has(memberId)) {
      skipped.push(memberId);
      continue;
    }
    seen.add(memberId);
    created.push({
      memberId,
      periodId: i.periodId,
      periodLabel: i.periodLabel,
      currency: i.currency,
      amountMinor: i.amountMinor,
      paidMinor: 0,
      dueDateMs: i.dueDateMs,
      cancelled: false,
      refunded: false,
      allowPartial: i.allowPartial,
      createdBy: i.actorId,
      createdAtMs: i.nowMs,
    });
  }
  return { created, skipped };
}
