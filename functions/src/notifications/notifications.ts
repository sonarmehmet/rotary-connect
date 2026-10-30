/**
 * Bildirim üreticileri. İlke (proje kuralı): bildirim metinlerinde TUTAR, ad, e-posta gibi
 * hassas finansal/kişisel bilgi bulunmaz; ayrıntı için uygulamaya güvenli girişle yönlendirilir.
 */
export type NotificationType =
  | "event_new"
  | "event_reminder"
  | "registration_confirmed"
  | "payment_result"
  | "due_reminder"
  | "due_paid"
  | "donation_confirmed"
  | "campaign"
  | "announcement";

export interface NotificationPrefs {
  readonly events: boolean;
  readonly dues: boolean;
  readonly donations: boolean;
  readonly announcements: boolean;
}

export const DEFAULT_PREFS: NotificationPrefs = {
  events: true,
  dues: true,
  donations: true,
  announcements: true,
};

export interface NotificationDoc {
  readonly userId: string;
  readonly type: NotificationType;
  readonly title: string;
  readonly body: string;
  readonly data: { readonly route: string; readonly refId: string };
  readonly read: boolean;
  readonly createdAtMs: number;
}

const CATEGORY: Record<NotificationType, keyof NotificationPrefs> = {
  event_new: "events",
  event_reminder: "events",
  registration_confirmed: "events",
  payment_result: "donations", // ödeme sonucu işlemsel: aşağıda tercihten bağımsız gönderilir
  due_reminder: "dues",
  due_paid: "dues",
  donation_confirmed: "donations",
  campaign: "donations",
  announcement: "announcements",
};

/** İşlemsel bildirimler (kullanıcının kendi başlattığı işlemin sonucu) tercihten bağımsız gider. */
const TRANSACTIONAL: ReadonlySet<NotificationType> = new Set([
  "payment_result",
  "registration_confirmed",
  "due_paid",
  "donation_confirmed",
]);

export function shouldSend(type: NotificationType, prefs: NotificationPrefs): boolean {
  return TRANSACTIONAL.has(type) || prefs[CATEGORY[type]];
}

const TEXT: Record<NotificationType, { title: string; body: string; route: string }> = {
  event_new: { title: "Yeni etkinlik", body: "Yeni bir etkinlik yayınlandı. Ayrıntılar için uygulamayı açın.", route: "/events" },
  event_reminder: { title: "Etkinlik hatırlatması", body: "Kayıtlı olduğunuz bir etkinlik yaklaşıyor.", route: "/events" },
  registration_confirmed: { title: "Kaydınız onaylandı", body: "Etkinlik kaydınız onaylandı.", route: "/events" },
  payment_result: { title: "Ödeme sonucu", body: "Ödeme işleminizin sonucu hazır. Görmek için uygulamayı açın.", route: "/profile" },
  due_reminder: { title: "Aidat hatırlatması", body: "Yaklaşan bir aidat son ödeme tarihiniz var.", route: "/dues" },
  due_paid: { title: "Tahsilat onayı", body: "Aidat ödemeniz alındı. Teşekkür ederiz.", route: "/dues" },
  donation_confirmed: { title: "Bağışınız alındı", body: "Bağışınız için teşekkür ederiz.", route: "/profile" },
  campaign: { title: "Yeni kampanya", body: "Yeni bir bağış kampanyası başladı.", route: "/donate" },
  announcement: { title: "Duyuru", body: "Kulüpten yeni bir duyuru var.", route: "/news" },
};

export function buildNotification(
  type: NotificationType,
  userId: string,
  refId: string,
  nowMs: number,
): NotificationDoc {
  const t = TEXT[type];
  return {
    userId,
    type,
    title: t.title,
    body: t.body,
    data: { route: t.route, refId },
    read: false,
    createdAtMs: nowMs,
  };
}

/** Hatırlatma zamanlaması: vadeden `daysBefore` gün önce, en fazla bir kez. */
export function dueReminderDue(
  dueDateMs: number,
  nowMs: number,
  daysBefore: number,
  alreadySent: boolean,
): boolean {
  if (alreadySent) return false;
  const windowStart = dueDateMs - daysBefore * 86_400_000;
  return nowMs >= windowStart && nowMs <= dueDateMs;
}
