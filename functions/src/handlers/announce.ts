import { buildAuditEntry } from "../audit/audit";
import { DomainError } from "../lib/errors";
import { ROLES, Role, requireRole } from "../lib/roles";
import {
  NotificationItem,
  NotificationPrefs,
  NotificationWriter,
  buildAnnouncementNotification,
  shouldSend,
} from "../notifications/notifications";
import { AuditSink, CallableAuth, requireAuth } from "./handlers";
import { asEnum, asObject, asString } from "./validate";

/**
 * `sendAnnouncement`: panelden duyuru/bildirim gönderimi (Hesap B isteği).
 * Yetki: içerik yöneticisi veya sistem yöneticisi. Metinde tutar, e-posta, telefon/TCKN benzeri
 * veri bulunamaz (proje kuralı: bildirimde hassas bilgi yok). Gönderim İDEMPOTENTTİR:
 * bildirim kimliği (yönetici + clientKey + alıcı) belirlidir, tekrar deneme çift bildirim üretmez.
 */
export type Audience =
  | { readonly type: "all" }
  | { readonly type: "members" }
  | { readonly type: "role"; readonly role: Role };

export interface Recipient {
  readonly userId: string;
  readonly prefs: NotificationPrefs;
}

export interface RecipientPage {
  readonly recipients: readonly Recipient[];
  readonly next: string | null;
}

export interface RecipientReader {
  /**
   * Hedef kitleyi sayfa sayfa okur. `role` hedefi Auth claim'lerine dayanır; uygulama bunu
   * (Admin SDK listUsers veya claim'i yansıtan bir dizin) ile çözmelidir.
   */
  page(audience: Audience, cursor: string | null, limit: number): Promise<RecipientPage>;
}

export type { NotificationItem, NotificationWriter } from "../notifications/notifications";

export interface AnnounceDeps {
  readonly recipients: RecipientReader;
  readonly notifications: NotificationWriter;
  readonly audit: AuditSink;
  readonly nowMs: () => number;
  readonly pageSize?: number;
}

const ANNOUNCERS: readonly Role[] = ["content_manager", "system_admin"];
/** Finansal ekran (/dues) bilerek yok: duyuru rotası kişisel finans verisine götürmez. */
export const ANNOUNCE_ROUTES = ["/news", "/events", "/projects", "/donate", "/profile"] as const;
const AUDIENCE_ROLES: readonly Role[] = ROLES.filter((r) => r !== "visitor");
const KEY = /^[A-Za-z0-9_-]{8,64}$/;
const BATCH = 400; // Firestore batch üst sınırı 500

const SENSITIVE: readonly RegExp[] = [
  /[^\s@]+@[^\s@]+/, // e-posta
  /\d(?:[ -]?\d){9,}/, // 10+ rakam: telefon, TCKN, IBAN parçası
  /\d[\d.,]*\s?(?:₺|tl\b|try\b|lira\b)/i, // tutar
  /\btr\d{2}\b/i, // IBAN başlangıcı
];

export function containsSensitive(text: string): boolean {
  return SENSITIVE.some((re) => re.test(text));
}

function parseAudience(v: unknown): Audience {
  const o = asObject(v, "audience");
  const type = asEnum(o["type"], "audience", ["all", "members", "role"] as const);
  if (type !== "role") return { type };
  return { type, role: asEnum(o["role"], "audience", AUDIENCE_ROLES as readonly Role[]) };
}

export async function sendAnnouncementHandler(
  deps: AnnounceDeps,
  auth: CallableAuth | null | undefined,
  data: unknown,
): Promise<{ recipients: number; sent: number; skippedByPreferences: number }> {
  const ctx = requireAuth(auth);
  requireRole(ctx.role, ANNOUNCERS);

  const o = asObject(data, "data");
  const audience = parseAudience(o["audience"]);
  const title = asString(o["title"], "title", { max: 80 });
  const body = asString(o["body"], "body", { max: 300 });
  const route = asEnum(o["route"], "route", ANNOUNCE_ROUTES);
  const clientKey = asString(o["clientKey"], "clientKey", { min: 8, max: 64 });
  if (!KEY.test(clientKey)) {
    throw new DomainError("invalid-argument", "clientKey alanı geçersiz", "invalid_clientKey");
  }
  if (containsSensitive(title) || containsSensitive(body)) {
    throw new DomainError(
      "invalid-argument",
      "Duyuru metni tutar, e-posta veya telefon gibi kişisel/finansal bilgi içeremez",
      "sensitive_content",
    );
  }

  const nowMs = deps.nowMs();
  const refId = `${ctx.uid}_${clientKey}`;
  const pageSize = deps.pageSize ?? 200;
  let cursor: string | null = null;
  let recipients = 0;
  let sent = 0;
  let skipped = 0;

  for (let guard = 0; guard < 10_000; guard++) {
    const page: RecipientPage = await deps.recipients.page(audience, cursor, pageSize);
    const items: NotificationItem[] = [];
    for (const r of page.recipients) {
      recipients++;
      if (!shouldSend("announcement", r.prefs)) {
        skipped++;
        continue;
      }
      items.push({
        id: `${refId}_${r.userId}`,
        doc: buildAnnouncementNotification({ userId: r.userId, title, body, route, refId, nowMs }),
      });
    }
    for (let i = 0; i < items.length; i += BATCH) {
      await deps.notifications.createIfAbsent(items.slice(i, i + BATCH));
    }
    sent += items.length;
    cursor = page.next;
    if (cursor === null) break;
  }

  await deps.audit.write(
    buildAuditEntry({
      actorId: ctx.uid,
      actorRole: ctx.role,
      action: "announcement.send",
      targetType: "announcement",
      targetId: refId,
      before: null,
      after: {
        audience: audience.type === "role" ? `role:${audience.role}` : audience.type,
        route,
        recipients,
        sent,
      },
      nowMs,
    }),
  );
  return { recipients, sent, skippedByPreferences: skipped };
}
