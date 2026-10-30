/** Denetim kaydı kurucusu. Kişisel/hassas alanlar kayda ASLA girmez (KVKK ve log güvenliği). */
export type AuditAction =
  | "payment.manual_record"
  | "refund.issue"
  | "role.assign"
  | "membership.approve"
  | "due.create"
  | "due.cancel"
  | "event.cancel"
  | "export.financial"
  | "settings.update"
  | "announcement.send";

export interface AuditEntry {
  readonly actorId: string;
  readonly actorRole: string;
  readonly action: AuditAction;
  readonly targetType: string;
  readonly targetId: string;
  readonly before: Record<string, unknown> | null;
  readonly after: Record<string, unknown> | null;
  readonly createdAtMs: number;
}

const SENSITIVE_KEYS = new Set([
  "email",
  "phone",
  "name",
  "displayName",
  "participant",
  "donor",
  "card",
  "cardNumber",
  "cvv",
  "token",
  "secret",
  "password",
  "iban",
  "tckn",
  "identityNumber",
  "fcmTokens",
]);

/** Hassas anahtarları (iç içe dahil) kaldırır; kalanı kopyalar. */
export function redact(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(redact);
  if (value && typeof value === "object") {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      if (SENSITIVE_KEYS.has(k)) continue;
      out[k] = redact(v);
    }
    return out;
  }
  return value;
}

export function buildAuditEntry(input: {
  actorId: string;
  actorRole: string;
  action: AuditAction;
  targetType: string;
  targetId: string;
  before?: Record<string, unknown> | null;
  after?: Record<string, unknown> | null;
  nowMs: number;
}): AuditEntry {
  return {
    actorId: input.actorId,
    actorRole: input.actorRole,
    action: input.action,
    targetType: input.targetType,
    targetId: input.targetId,
    before: input.before ? (redact(input.before) as Record<string, unknown>) : null,
    after: input.after ? (redact(input.after) as Record<string, unknown>) : null,
    createdAtMs: input.nowMs,
  };
}
