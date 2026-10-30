import { DomainError } from "../lib/errors";

/**
 * Güvenilmeyen istemci girdisi için doğrulayıcılar. Her hata `invalid-argument` ve
 * `reason: invalid_<alan>` döner; istemci alan bazlı Türkçe mesaj gösterebilir.
 * Bilinmeyen alanlar çağıran tarafta hiç okunmadığı için sessizce yok sayılır.
 */
function bad(field: string): never {
  throw new DomainError("invalid-argument", `${field} alanı geçersiz`, `invalid_${field}`);
}

const CONTROL = /[\u0000-\u001f\u007f]/;
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const PHONE = /^[0-9+()\-\s]{5,20}$/;

export function asObject(v: unknown, field: string): Record<string, unknown> {
  if (typeof v !== "object" || v === null || Array.isArray(v)) return bad(field);
  return v as Record<string, unknown>;
}

export function asString(v: unknown, field: string, o: { min?: number; max?: number } = {}): string {
  if (typeof v !== "string") return bad(field);
  const s = v.trim();
  if (CONTROL.test(s)) return bad(field);
  if (s.length < (o.min ?? 1) || s.length > (o.max ?? 200)) return bad(field);
  return s;
}

export function asOptionalString(
  v: unknown,
  field: string,
  o: { min?: number; max?: number } = {},
): string | undefined {
  return v === undefined || v === null ? undefined : asString(v, field, o);
}

export function asEmail(v: unknown, field = "email"): string {
  const s = asString(v, field, { max: 254 });
  return EMAIL.test(s) ? s.toLowerCase() : bad(field);
}

export function asOptionalPhone(v: unknown, field = "phone"): string | undefined {
  const s = asOptionalString(v, field, { max: 20 });
  if (s === undefined) return undefined;
  return PHONE.test(s) ? s : bad(field);
}

export function asInt(v: unknown, field: string, o: { min: number; max: number }): number {
  if (typeof v !== "number" || !Number.isSafeInteger(v) || v < o.min || v > o.max) return bad(field);
  return v;
}

export function asBool(v: unknown, field: string, fallback = false): boolean {
  if (v === undefined || v === null) return fallback;
  return typeof v === "boolean" ? v : bad(field);
}

export function asEnum<T extends string>(v: unknown, field: string, allowed: readonly T[]): T {
  return typeof v === "string" && (allowed as readonly string[]).includes(v) ? (v as T) : bad(field);
}
