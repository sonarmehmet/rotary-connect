import { EventRegistrationService } from "../events/service";
import { DueDoc, deriveDueStatus } from "../dues/dues";
import { NotificationWriter, buildNotification, dueReminderDue } from "../notifications/notifications";
import { ReconcileOptions, ReconcileReport, reconcilePending } from "../payments/reconcile";
import { PaymentProvider } from "../payments/provider";
import { PaymentTxRunner } from "../payments/repo";

/**
 * Zamanlanmış işlerin SDK'dan bağımsız gövdeleri. Firebase `onSchedule` sarmalayıcısı yalnızca
 * bu fonksiyonları çağırır. Hepsi tekrar çalıştırılabilir (idempotent) olacak şekilde yazıldı.
 */

export interface OpenEventSource {
  /** Aktif rezervasyonu (`reserved`) olabilecek etkinlik kimlikleri. */
  listEventIdsWithReservations(limit: number): Promise<readonly string[]>;
}

export interface ExpireReport {
  readonly events: number;
  readonly expired: number;
  readonly promoted: number;
  readonly errors: number;
}

/** Her etkinlik için süresi dolan rezervasyonları düşürür ve bekleme listesini ilerletir. */
export async function runExpireReservations(
  source: OpenEventSource,
  svc: EventRegistrationService,
  nowMs: number,
  reservationMinutes: number,
  limit = 200,
): Promise<ExpireReport> {
  const ids = await source.listEventIdsWithReservations(limit);
  let expired = 0;
  let promoted = 0;
  let errors = 0;
  for (const id of ids) {
    try {
      const r = await svc.expireReservations(id, nowMs, reservationMinutes);
      expired += r.expired.length;
      promoted += r.promoted.length;
    } catch {
      errors++; // tek etkinliğin hatası diğerlerini durdurmaz
    }
  }
  return { events: ids.length, expired, promoted, errors };
}

export interface DueRow extends DueDoc {
  readonly id: string;
  readonly userId: string;
  readonly status: string;
  readonly reminderSent: boolean;
}

export interface DueSource {
  /** Ödenmemiş/kısmi/gecikmiş (kapanmamış) borçlar, sayfalı. */
  listOpenDues(cursor: string | null, limit: number): Promise<{ rows: readonly DueRow[]; next: string | null }>;
}

export interface DueSink {
  setStatus(dueId: string, status: string): Promise<void>;
  markReminderSent(dueId: string, nowMs: number): Promise<void>;
}

export interface DueJobReport {
  readonly checked: number;
  readonly markedOverdue: number;
  readonly reminded: number;
}

/**
 * Günlük aidat işi: vadesi geçeni `overdue` yapar, vadeye `daysBefore` gün kalanlara
 * (kayıtlı kullanıcıya) tek seferlik hatırlatma bildirimi üretir. Bildirim kimliği borç başına
 * belirlidir, iş iki kez çalışsa da çift bildirim oluşmaz.
 */
export async function runDueMaintenance(
  source: DueSource,
  sink: DueSink,
  notifications: NotificationWriter,
  nowMs: number,
  daysBefore: number,
  pageSize = 200,
): Promise<DueJobReport> {
  let cursor: string | null = null;
  let checked = 0;
  let markedOverdue = 0;
  let reminded = 0;
  for (let guard = 0; guard < 10_000; guard++) {
    const page = await source.listOpenDues(cursor, pageSize);
    for (const d of page.rows) {
      checked++;
      const status = deriveDueStatus(d, nowMs);
      if (status === "overdue" && d.status !== "overdue") {
        await sink.setStatus(d.id, "overdue");
        markedOverdue++;
      }
      if (status !== "overdue" && dueReminderDue(d.dueDateMs, nowMs, daysBefore, d.reminderSent)) {
        await notifications.createIfAbsent([
          { id: `rem_${d.id}`, doc: buildNotification("due_reminder", d.userId, d.id, nowMs) },
        ]);
        await sink.markReminderSent(d.id, nowMs);
        reminded++;
      }
    }
    cursor = page.next;
    if (cursor === null) break;
  }
  return { checked, markedOverdue, reminded };
}

/** Ödeme mutabakatı işi: ince sarmalayıcı (sağlayıcıdan sunucu-sunucu sorgu). */
export function runReconcile(
  runner: PaymentTxRunner,
  provider: PaymentProvider,
  opts: ReconcileOptions,
): Promise<ReconcileReport> {
  return reconcilePending(runner, provider, opts);
}
