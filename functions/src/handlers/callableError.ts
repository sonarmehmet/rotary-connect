import { DomainError, ErrorCode } from "../lib/errors";
import { PermissionDeniedError } from "../lib/roles";

export type CallableCode = ErrorCode | "internal";

/**
 * İstemciye giden hata biçimi. Firebase sarmalayıcısı bunu `HttpsError(code, message, {reason})`
 * olarak fırlatır. Beklenmeyen hatalarda iç ayrıntı (yığın, sorgu, kimlik) ASLA sızdırılmaz.
 */
export interface CallableErrorShape {
  readonly code: CallableCode;
  readonly message: string;
  readonly reason: string | null;
}

export const INTERNAL_MESSAGE = "Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.";

export function toCallableError(e: unknown): CallableErrorShape {
  if (e instanceof DomainError) {
    return { code: e.code, message: e.message, reason: e.reason ?? null };
  }
  if (e instanceof PermissionDeniedError) {
    return { code: "permission-denied", message: e.message, reason: null };
  }
  return { code: "internal", message: INTERNAL_MESSAGE, reason: null };
}
