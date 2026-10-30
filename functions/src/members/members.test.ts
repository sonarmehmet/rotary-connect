import { describe, expect, it } from "vitest";
import { DomainError } from "../lib/errors";
import {
  DEFAULT_PREFS,
  buildNotification,
  dueReminderDue,
  shouldSend,
} from "../notifications/notifications";
import { anonymizeRecord, planAccountDeletion } from "../privacy/deletion";
import { MemberDoc, approveMembership, assignDues, endMembership, requestMembership } from "./members";

const NOW = 1_800_000_000_000;
const DAY = 86_400_000;

const pendingMember: MemberDoc = {
  userId: "u1",
  memberNo: null,
  status: "pending",
  requestedAtMs: NOW - DAY,
  joinedAtMs: null,
  approvedBy: null,
};

function reason(fn: () => unknown): string {
  try {
    fn();
    return "no-error";
  } catch (e) {
    return e instanceof DomainError ? (e.reason ?? e.code) : e instanceof Error ? e.name : "other";
  }
}

describe("üyelik", () => {
  it("talep açılır; tekrar talep engellenir, reddedilmiş/istifa edilmişse yeniden açılabilir", () => {
    const m = requestMembership(null, "u1", NOW);
    expect(m.status).toBe("pending");
    expect(reason(() => requestMembership(m, "u1", NOW))).toBe("already_requested");
    expect(requestMembership({ ...m, status: "resigned" }, "u1", NOW).status).toBe("pending");
  });

  it("yalnızca sistem yöneticisi onaylar; club_member rolü verilir", () => {
    const r = approveMembership("system_admin", "adm", pendingMember, "registered_user", "A-101", NOW);
    expect(r.member.status).toBe("active");
    expect(r.member.approvedBy).toBe("adm");
    expect(r.newRole).toBe("club_member");
    for (const role of ["finance_manager", "content_manager", "club_member", "visitor"]) {
      expect(reason(() => approveMembership(role, "x", pendingMember, "registered_user", "A-1", NOW))).toBe(
        "PermissionDeniedError",
      );
    }
  });

  it("yönetici rolü onayla düşürülmez", () => {
    expect(approveMembership("system_admin", "a", pendingMember, "finance_manager", "A-1", NOW).newRole).toBe(
      "finance_manager",
    );
  });

  it("bekleyen olmayan talep onaylanamaz; üye numarası zorunlu", () => {
    const active = { ...pendingMember, status: "active" as const };
    expect(reason(() => approveMembership("system_admin", "a", active, "club_member", "A-1", NOW))).toBe("not_pending");
    expect(reason(() => approveMembership("system_admin", "a", pendingMember, "registered_user", "  ", NOW))).toBe(
      "member_no_required",
    );
  });

  it("üyelik sonlanınca club_member yetkisi kalkar", () => {
    const active = { ...pendingMember, status: "active" as const };
    expect(endMembership("system_admin", active, "suspended", "club_member").newRole).toBe("registered_user");
    expect(endMembership("system_admin", active, "resigned", "content_manager").newRole).toBe("content_manager");
    expect(reason(() => endMembership("system_admin", pendingMember, "resigned", "club_member"))).toBe("not_active");
  });
});

describe("toplu aidat atama", () => {
  const base = {
    actorRole: "finance_manager",
    actorId: "fin",
    periodId: "2026-2027",
    periodLabel: "2026-2027",
    amountMinor: 120_000,
    currency: "TRY",
    dueDateMs: NOW + 30 * DAY,
    allowPartial: false,
    nowMs: NOW,
    activeMemberIds: ["m1", "m2", "m3", "m2"],
    alreadyAssignedMemberIds: new Set(["m3"]),
  };

  it("her üyeye bir borç; mükerrer ve zaten atanmış üyeler atlanır", () => {
    const { created, skipped } = assignDues(base);
    expect(created.map((c) => c.memberId)).toEqual(["m1", "m2"]);
    expect(skipped).toEqual(["m3", "m2"]); // sıra: m3 zaten atanmış, sonra tekrar eden m2
    expect(created[0]?.paidMinor).toBe(0);
    expect(created[0]?.createdBy).toBe("fin");
  });

  it("yalnızca finans yöneticisi atayabilir", () => {
    for (const role of ["system_admin", "content_manager", "club_member"]) {
      expect(reason(() => assignDues({ ...base, actorRole: role }))).toBe("PermissionDeniedError");
    }
  });

  it("geçersiz tutar ve geçmiş tarih reddedilir", () => {
    expect(reason(() => assignDues({ ...base, amountMinor: 0 }))).toBe("invalid_amount");
    expect(reason(() => assignDues({ ...base, amountMinor: 10.5 }))).toBe("invalid_amount");
    expect(reason(() => assignDues({ ...base, dueDateMs: NOW - 1 }))).toBe("due_date_in_past");
  });
});

describe("bildirimler", () => {
  it("metinlerde tutar, e-posta veya ad bulunmaz", () => {
    const types = [
      "event_new", "event_reminder", "registration_confirmed", "payment_result",
      "due_reminder", "due_paid", "donation_confirmed", "campaign", "announcement",
    ] as const;
    for (const t of types) {
      const n = buildNotification(t, "u1", "ref1", NOW);
      expect(/\d+\s?(₺|TL)|@/.test(`${n.title} ${n.body}`)).toBe(false);
      expect(n.read).toBe(false);
      expect(n.data.route.startsWith("/")).toBe(true);
    }
  });

  it("tercihler pazarlama benzeri bildirimleri keser, işlemsel olanları kesmez", () => {
    const off = { events: false, dues: false, donations: false, announcements: false };
    expect(shouldSend("event_new", off)).toBe(false);
    expect(shouldSend("due_reminder", off)).toBe(false);
    expect(shouldSend("campaign", off)).toBe(false);
    expect(shouldSend("announcement", off)).toBe(false);
    expect(shouldSend("payment_result", off)).toBe(true);
    expect(shouldSend("registration_confirmed", off)).toBe(true);
    expect(shouldSend("due_paid", off)).toBe(true);
    expect(shouldSend("event_new", DEFAULT_PREFS)).toBe(true);
  });

  it("aidat hatırlatması penceresi ve tek seferlik gönderim", () => {
    const due = NOW + 7 * DAY;
    expect(dueReminderDue(due, NOW, 7, false)).toBe(true);
    expect(dueReminderDue(due, NOW - 1, 7, false)).toBe(false); // henüz erken
    expect(dueReminderDue(due, due + 1, 7, false)).toBe(false); // vade geçti
    expect(dueReminderDue(due, NOW, 7, true)).toBe(false); // zaten gönderildi
  });
});

describe("KVKK hesap silme", () => {
  it("engel yoksa ilerler; finansal kayıtlar silinmez, anonimleştirilir", () => {
    const plan = planAccountDeletion({ userId: "u1", hasPendingPayments: false, hasOutstandingDues: false, hasFutureEventRegistrations: false });
    expect(plan.canProceed).toBe(true);
    expect(plan.delete.some((d) => d.startsWith("payments"))).toBe(false);
    expect(plan.anonymize.some((a) => a.startsWith("payments"))).toBe(true);
  });

  it("bekleyen ödeme, borç veya gelecek etkinlik kaydı silmeyi engeller", () => {
    const plan = planAccountDeletion({ userId: "u1", hasPendingPayments: true, hasOutstandingDues: true, hasFutureEventRegistrations: true });
    expect(plan.canProceed).toBe(false);
    expect(plan.blockers).toEqual(["pending_payments", "outstanding_dues", "future_event_registrations"]);
  });

  it("anonimleştirme kişisel alanları temizler, finansal alanları korur", () => {
    const out = anonymizeRecord({
      userId: "u1",
      amountMinor: 5000,
      status: "succeeded",
      donor: { name: "Ali", email: "a@b.c" },
      email: "a@b.c",
    });
    expect(out.userId).toBe("silinmiş-kullanıcı");
    expect(out.amountMinor).toBe(5000);
    expect(out.status).toBe("succeeded");
    expect(JSON.stringify(out).includes("a@b.c")).toBe(false);
    expect("email" in out).toBe(false);
  });
});
