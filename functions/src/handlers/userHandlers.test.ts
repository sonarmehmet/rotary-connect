import { describe, expect, it } from "vitest";
import { AuditEntry } from "../audit/audit";
import { EventRegistrationService } from "../events/service";
import { NotificationItem } from "../notifications/notifications";
import { MemoryStore } from "../testing/memoryStore";
import { runDueMaintenance, runExpireReservations, DueRow } from "../jobs/scheduled";
import { toCallableError } from "./callableError";
import { CallableAuth } from "./handlers";
import { ReceiptRow, getDonationReceiptHandler, requestAccountDeletionHandler } from "./userHandlers";

const NOW = 1_800_000_000_000;
const DAY = 86_400_000;
const auth = (uid: string): CallableAuth => ({ uid, token: {} });

async function failure(p: Promise<unknown>): Promise<string> {
  try {
    await p;
    return "no-error";
  } catch (e) {
    const c = toCallableError(e);
    return `${c.code}:${c.reason ?? ""}`;
  }
}

const row = (over: Partial<ReceiptRow> = {}): ReceiptRow => ({
  id: "d1", paymentId: "p1", userId: "u1", donorEmail: "ali@example.com", donorName: "Ali Veli", anonymous: false,
  amountMinor: 25_000, currency: "TRY", status: "succeeded", receiptNo: "MK-1", campaignId: "c1", simulated: false,
  createdAtMs: NOW, ...over,
});
const readerOf = (r: ReceiptRow | null) => ({ receipts: { getByDonationId: async () => r } });

describe("bağış makbuzu", () => {
  it("sahip makbuz alır; anonim bağışta ad gizlenir", async () => {
    const out = await getDonationReceiptHandler(readerOf(row({ anonymous: true })), auth("u1"), { donationId: "d1" });
    expect(out.receiptNo).toBe("MK-1");
    expect(out.donorName).toBe("Anonim bağışçı");
  });

  it("başka kullanıcı ve olmayan bağış aynı hatayı alır", async () => {
    expect(await failure(getDonationReceiptHandler(readerOf(row()), auth("u2"), { donationId: "d1" }))).toBe("not-found:donation_not_found");
    expect(await failure(getDonationReceiptHandler(readerOf(null), auth("u1"), { donationId: "d1" }))).toBe("not-found:donation_not_found");
  });

  it("misafir yalnızca doğru e-posta ile (büyük/küçük harf fark etmez) alır", async () => {
    const guest = readerOf(row({ userId: null }));
    const ok = await getDonationReceiptHandler(guest, null, { donationId: "d1", email: "ALI@example.com" });
    expect(ok.receiptNo).toBe("MK-1");
    expect(await failure(getDonationReceiptHandler(guest, null, { donationId: "d1", email: "x@example.com" }))).toBe("not-found:donation_not_found");
    expect(await failure(getDonationReceiptHandler(guest, null, { donationId: "d1" }))).toBe("invalid-argument:invalid_email");
  });

  it("misafir, giriş yapmış kullanıcıya ait bağışa e-postayla ulaşamaz", async () => {
    expect(await failure(getDonationReceiptHandler(readerOf(row()), null, { donationId: "d1", email: "ali@example.com" }))).toBe("not-found:donation_not_found");
  });

  it("başarısız veya makbuzsuz bağışa makbuz verilmez; simülasyon işaretlenir", async () => {
    expect(await failure(getDonationReceiptHandler(readerOf(row({ status: "pending", receiptNo: null })), auth("u1"), { donationId: "d1" }))).toBe("failed-precondition:receipt_unavailable");
    expect((await getDonationReceiptHandler(readerOf(row({ simulated: true })), auth("u1"), { donationId: "d1" })).simulated).toBe(true);
  });
});

function deletionDeps(f: { pending?: boolean; dues?: boolean; regs?: boolean } = {}) {
  const audits: AuditEntry[] = [];
  const opened = new Set<string>();
  return {
    audits,
    deps: {
      facts: {
        hasPendingPayments: async () => f.pending ?? false,
        hasOutstandingDues: async () => f.dues ?? false,
        hasFutureEventRegistrations: async () => f.regs ?? false,
      },
      requests: { open: async (uid: string) => ({ created: !opened.has(uid) && (opened.add(uid), true) }) },
      audit: { write: async (e: AuditEntry) => void audits.push(e) },
      nowMs: () => NOW,
    },
  };
}

describe("hesap silme talebi", () => {
  it("engel yoksa talep açılır ve denetim yazılır; tekrar çağrı çift kayıt açmaz", async () => {
    const { deps, audits } = deletionDeps();
    expect(await requestAccountDeletionHandler(deps, auth("u1"), {})).toEqual({ accepted: true, blockers: [], alreadyRequested: false });
    expect(await requestAccountDeletionHandler(deps, auth("u1"), {})).toEqual({ accepted: true, blockers: [], alreadyRequested: true });
    expect(audits.length).toBe(1);
  });

  it("açık ödeme, borç veya gelecek etkinlik talebi engeller", async () => {
    const { deps, audits } = deletionDeps({ pending: true, dues: true });
    const out = await requestAccountDeletionHandler(deps, auth("u1"), {});
    expect(out.accepted).toBe(false);
    expect(out.blockers).toEqual(["pending_payments", "outstanding_dues"]);
    expect(audits.length).toBe(0);
  });

  it("girişsiz çağrı reddedilir", async () => {
    expect(await failure(requestAccountDeletionHandler(deletionDeps().deps, null, {}))).toBe("unauthenticated:login_required");
  });
});

describe("zamanlanmış işler", () => {
  it("rezervasyon süresi dolum işi bir etkinliğin hatasında diğerlerine devam eder", async () => {
    const ev = (id: string) => ({
      id, capacity: 1, reservedCount: 0, confirmedCount: 0, waitlistEnabled: true, status: "published" as const,
      registrationDeadlineMs: NOW + DAY, feeMinor: 100, currency: "TRY",
    });
    const svc = new EventRegistrationService(new MemoryStore([ev("a"), ev("b")]));
    await svc.reserveSpot({ eventId: "a", userId: "u1", participant: { name: "A", email: "a@b.co" }, nowMs: NOW, reservationMinutes: 10 });
    const source = { listEventIdsWithReservations: async () => ["a", "yok", "b"] };
    const r = await runExpireReservations(source, svc, NOW + 11 * 60_000, 10);
    expect(r).toEqual({ events: 3, expired: 1, promoted: 0, errors: 1 });
    const again = await runExpireReservations(source, svc, NOW + 12 * 60_000, 10);
    expect(again.expired).toBe(0);
  });

  it("aidat işi gecikmeyi işaretler, hatırlatmayı bir kez üretir", async () => {
    const dues: DueRow[] = [
      { id: "d1", userId: "u1", status: "unpaid", reminderSent: false, amountMinor: 100, paidMinor: 0, dueDateMs: NOW - DAY, cancelled: false, refunded: false, allowPartial: false },
      { id: "d2", userId: "u2", status: "unpaid", reminderSent: false, amountMinor: 100, paidMinor: 0, dueDateMs: NOW + 2 * DAY, cancelled: false, refunded: false, allowPartial: false },
      { id: "d3", userId: "u3", status: "unpaid", reminderSent: false, amountMinor: 100, paidMinor: 0, dueDateMs: NOW + 30 * DAY, cancelled: false, refunded: false, allowPartial: false },
    ];
    const statuses = new Map<string, string>();
    const reminded = new Set<string>();
    const notes = new Map<string, NotificationItem>();
    const run = () =>
      runDueMaintenance(
        { listOpenDues: async () => ({ rows: dues.map((d) => ({ ...d, reminderSent: reminded.has(d.id) })), next: null }) },
        { setStatus: async (id, s) => void statuses.set(id, s), markReminderSent: async (id) => void reminded.add(id) },
        { createIfAbsent: async (items) => void items.forEach((i) => notes.set(i.id, i)) },
        NOW, 3,
      );
    expect(await run()).toEqual({ checked: 3, markedOverdue: 1, reminded: 1 });
    expect(statuses.get("d1")).toBe("overdue");
    expect([...notes.keys()]).toEqual(["rem_d2"]);
    expect((await run()).reminded).toBe(0);
    expect(notes.size).toBe(1);
  });
});
