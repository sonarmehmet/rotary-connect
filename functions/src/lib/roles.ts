/** packages/shared/lib/src/roles.dart ile aynı rol adları. */
export const ROLES = [
  "visitor",
  "registered_user",
  "club_member",
  "content_manager",
  "finance_manager",
  "system_admin",
] as const;

export type Role = (typeof ROLES)[number];

export function parseRole(value: unknown): Role {
  return (ROLES as readonly string[]).includes(value as string)
    ? (value as Role)
    : "visitor";
}

export class PermissionDeniedError extends Error {
  constructor(message = "Bu işlem için yetkiniz yok") {
    super(message);
    this.name = "PermissionDeniedError";
  }
}

/** Her callable function başında çağrılır: rol izin verilenler arasında değilse reddeder. */
export function requireRole(role: unknown, allowed: readonly Role[]): Role {
  const parsed = parseRole(role);
  if (!allowed.includes(parsed)) {
    throw new PermissionDeniedError();
  }
  return parsed;
}
