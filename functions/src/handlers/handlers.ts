import { AuditEntry, buildAuditEntry } from "../audit/audit";
import { EventRegistrationService } from "../events/service";
import { DomainError } from "../lib/errors";
import { Role, parseRole, requireRole } from "../lib/roles";
import { DonationLimits, resolveDonationAmount } from "../payments/amounts";
import { recordManualPayment } from "../payments/manual";
import { PaymentProvider } from "../payments/provider";
import { PaymentTxRunner } from "../payments/repo";
import { startPayment } from "../payments/startPayment";
import {
  asBool,
  asEmail,
  asEnum,
  asInt,
  asObject,
  asOptionalPhone,
  asOptionalString,
  asString,
} from "./validate";

/**
 * Sunucu sınırı işleyicileri. Firebase `onCall` sarmalayıcısı yalnızca (auth, data) geçirir ve
 * hataları `toCallableError` ile çevirir. İşleyiciler SDK'dan bağımsızdır, bu yüzden test edilebilir.
 * İlke: yetki ÖNCE (girdiyi okumadan), sonra doğrulama, sonra iş kuralı.
 */
export interface CallableAuth {
  readonly uid: string;
  readonly token: Readonly<Record<string, unknown>>;
}

export interface AuthContext {
  readonly uid: string;
  readonly role: Role;
}

/** Oturum zorunlu. Rol claim'i yoksa `registered_user` (Firestore kurallarıyla aynı varsayılan). */
export function requireAuth(auth: CallableAuth | null | undefined): AuthContext {
  if (!auth || typeof auth.uid !== "string" || auth.uid.length === 0) {
    throw new DomainError("unauthenticated", "Bu işlem için giriş yapmalısınız", "login_required");
  }
  const claim = auth.token["role"];
  return { uid: auth.uid, role: claim === undefined ? "registered_user" : parseRole(claim) };
}

export interface AuditSink {
  write(entry: AuditEntry): Promise<void>;
}

// ---------------------------------------------------------------- etkinlik kaydı

export interface EventHandlerDeps {
  readonly events: EventRegistrationService;
  readonly nowMs: () => number;
  readonly reservationMinutes: number;
}

export async function reserveEventSpotHandler(
  deps: EventHandlerDeps,
  auth: CallableAuth | null | undefined,
  data: unknown,
): Promise<{
  registrationId: string;
  status: string;
  reservedUntilMs: number | null;
  waitlistPosition: number | null;
}> {
  const ctx = requireAuth(auth);
  const o = asObject(data, "data");
  const eventId = asString(o["eventId"], "eventId", { max: 100 });
  const p = asObject(o["participant"], "participant");
  const phone = asOptionalPhone(p["phone"]);
  const participant = {
    name: asString(p["name"], "name", { max: 100 }),
    email: asEmail(p["email"]),
    ...(phone === undefined ? {} : { phone }),
  };
  const { registration } = await deps.events.reserveSpot({
    eventId,
    userId: ctx.uid,
    participant,
    nowMs: deps.nowMs(),
    reservationMinutes: deps.reservationMinutes,
  });
  return {
    registrationId: registration.id,
    status: registration.status,
    reservedUntilMs: registration.reservedUntilMs,
    waitlistPosition: registration.waitlistPosition,
  };
}

const EVENT_STAFF: readonly Role[] = ["content_manager", "system_admin"];

export async function cancelRegistrationHandler(
  deps: EventHandlerDeps,
  auth: CallableAuth | null | undefined,
  data: unknown,
): Promise<{ promotedCount: number; refundRequired: boolean }> {
  const ctx = requireAuth(auth);
  const o = asObject(data, "data");
  const registrationId = asString(o["registrationId"], "registrationId", { max: 100 });
  const out = await deps.events.cancelRegistration({
    registrationId,
    actorUserId: ctx.uid,
    actorIsStaff: EVENT_STAFF.includes(ctx.role),
    nowMs: deps.nowMs(),
    reservationMinutes: deps.reservationMinutes,
  });
  return { promotedCount: out.promoted.length, refundRequired: out.refundRequired };
}

// ---------------------------------------------------------------- bağış

export interface CampaignInfo {
  readonly status: "draft" | "active" | "completed" | "archived";
  readonly currency: string;
}

export interface CampaignReader {
  get(id: string): Promise<CampaignInfo | null>;
}

export interface PendingDonation {
  readonly paymentId: string;
  readonly campaignId: string | null;
  readonly userId: string | null;
  readonly donor: { readonly name: string; readonly email: string; readonly anonymous: boolean };
  readonly amountMinor: number;
  readonly currency: string;
  readonly nowMs: number;
}

/** Bağış kaydını ödeme ile aynı anda `pending` açar; durumu ödeme durumunu izler. */
export interface DonationRecorder {
  createPending(d: PendingDonation): Promise<void>;
}

export interface DonationHandlerDeps {
  readonly payments: PaymentTxRunner;
  readonly provider: PaymentProvider;
  readonly campaigns: CampaignReader;
  readonly donations: DonationRecorder;
  readonly nowMs: () => number;
  readonly mode: "simulation" | "live";
  readonly newId: () => string;
  readonly limits?: DonationLimits;
}

/** Misafir bağışı serbesttir (auth yok); oturum varsa ödeme kullanıcıya bağlanır. */
export async function startDonationHandler(
  deps: DonationHandlerDeps,
  auth: CallableAuth | null | undefined,
  data: unknown,
): Promise<{
  paymentId: string;
  status: string;
  checkoutUrl: string | null;
  simulated: boolean;
  reused: boolean;
}> {
  const userId = auth ? requireAuth(auth).uid : null;
  const o = asObject(data, "data");
  const campaignId = asOptionalString(o["campaignId"], "campaignId", { max: 100 }) ?? null;
  const d = asObject(o["donor"], "donor");
  const donor = {
    name: asString(d["name"], "name", { max: 100 }),
    email: asEmail(d["email"]),
    anonymous: asBool(d["anonymous"], "anonymous"),
  };
  const clientKey = asString(o["clientKey"], "clientKey", { min: 8, max: 100 });

  let currency = "TRY";
  if (campaignId !== null) {
    const c = await deps.campaigns.get(campaignId);
    if (!c) throw new DomainError("not-found", "Kampanya bulunamadı", "campaign_not_found");
    if (c.status !== "active") {
      throw new DomainError("failed-precondition", "Bu kampanya şu an bağış kabul etmiyor", "campaign_not_active");
    }
    currency = c.currency;
  }
  const amount = resolveDonationAmount(o["amountMinor"], deps.limits, currency);
  const nowMs = deps.nowMs();

  const result = await startPayment(deps.payments, deps.provider, {
    kind: "donation",
    refId: campaignId ?? "general",
    userId,
    amount,
    clientKey,
    description: "Bağış",
    nowMs,
    mode: deps.mode,
    newId: deps.newId,
  });
  if (!result.reused) {
    await deps.donations.createPending({
      paymentId: result.payment.id,
      campaignId,
      userId,
      donor,
      amountMinor: amount.amountMinor,
      currency: amount.currency,
      nowMs,
    });
  }
  return {
    paymentId: result.payment.id,
    status: result.payment.status,
    checkoutUrl: result.checkoutUrl,
    simulated: result.payment.simulated,
    reused: result.reused,
  };
}

// ---------------------------------------------------------------- manuel ödeme

export interface ManualPaymentDeps {
  readonly payments: PaymentTxRunner;
  readonly audit: AuditSink;
  readonly nowMs: () => number;
}

/**
 * Yalnızca finans yöneticisi. Yetki girdiyi okumadan ÖNCE denetlenir (yetkisiz kişi hiçbir
 * doğrulama ipucu almaz). Her kayıt denetim günlüğüne yazılır.
 * Bilinen sınır: ödeme ve denetim kaydı ayrı yazılır; Firestore adaptöründe tek transaction'a alınmalıdır.
 */
export async function recordManualPaymentHandler(
  deps: ManualPaymentDeps,
  auth: CallableAuth | null | undefined,
  data: unknown,
): Promise<{ paymentId: string }> {
  const ctx = requireAuth(auth);
  requireRole(ctx.role, ["finance_manager"]);
  const o = asObject(data, "data");
  const input = {
    kind: asEnum(o["kind"], "kind", ["membership_due", "donation", "event_fee"] as const),
    refId: asString(o["refId"], "refId", { max: 100 }),
    userId: asOptionalString(o["userId"], "userId", { max: 128 }) ?? null,
    amountMinor: asInt(o["amountMinor"], "amountMinor", { min: 1, max: 1_000_000_000 }),
    receivedAtMs: asInt(o["receivedAtMs"], "receivedAtMs", { min: 0, max: Number.MAX_SAFE_INTEGER }),
    note: asString(o["note"], "note", { min: 5, max: 500 }),
  };
  const nowMs = deps.nowMs();
  const payment = await recordManualPayment(deps.payments, {
    ...input,
    currency: "TRY",
    actorRole: ctx.role,
    actorId: ctx.uid,
    nowMs,
  });
  await deps.audit.write(
    buildAuditEntry({
      actorId: ctx.uid,
      actorRole: ctx.role,
      action: "payment.manual_record",
      targetType: "payment",
      targetId: payment.id,
      before: null,
      after: { kind: input.kind, refId: input.refId, amountMinor: input.amountMinor, manual: true },
      nowMs,
    }),
  );
  return { paymentId: payment.id };
}
