/**
 * İş kuralı hataları. `code` değerleri Firebase callable hata kodlarıyla aynıdır
 * (DATA_MODEL.md / TASKS.md "Entegrasyon sözleşmeleri"); istemci bunları Türkçe mesaja eşler.
 * `reason` makine tarafından okunabilir ince ayrımdır (ör. "sold_out").
 */
export type ErrorCode =
  | "unauthenticated"
  | "permission-denied"
  | "invalid-argument"
  | "failed-precondition"
  | "already-exists"
  | "not-found"
  | "unavailable";

export class DomainError extends Error {
  constructor(
    readonly code: ErrorCode,
    message: string,
    readonly reason?: string,
  ) {
    super(message);
    this.name = "DomainError";
  }
}
