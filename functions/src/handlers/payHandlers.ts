import { DueDoc } from "../dues/dues";
import { resolveDuePayment } from "../dues/dues";
import { RegistrationDoc } from "../events/capacity";
import { DomainError } from "../lib/errors";
import { resolveEventFee } from "../payments/amounts";
import { PaymentProvider } from "../payments/provider";
import { PaymentTxRunner } from "../payments/repo";
import { startPayment } from "../payments/startPayment";
import { CallableAuth, requireAuth } from "./handlers";
import { asInt, asObject, asString } from "./validate";

/**
 * Üye aidat ve etkinlik ücreti ödemesini başlatır. Tutar HER ZAMAN sunucuda kayıttan çözülür;
 * istemci yalnızca (izin varsa) aidatta kısmi tutar önerebilir. Başkasının borcu/kaydı için
 * ödeme açılamaz (sahiplik kontrolü; kayıt yoksa ve sahip değilse aynı "not-found" döner).
 */
export interface PayHandlerDeps {
  readonly payments: PaymentTxRunner;
  readonly provider: PaymentProvider;
  readonly nowMs: () => number;
  readonly mode: "simulation" | "live";
  readonly newId: () => string;
}

export interface DueReader {
  get(id: string): Promise<(DueDoc & { userId: string; currency: string }) | null>;
}

export interface RegistrationReader {
  get(id: string): Promise<RegistrationDoc | null>;
  eventFee(eventId: string): Promise<{ feeMinor: number; currency: string } | null>;
}

export interface PayResult {
  paymentId: string;
  status: string;
  checkoutUrl: string | null;
  simulated: boolean;
  reused: boolean;
}

function toResult(r: Awaited<ReturnType<typeof startPayment>>): PayResult {
  return {
    paymentId: r.payment.id,
    status: r.payment.status,
    checkoutUrl: r.checkoutUrl,
    simulated: r.payment.simulated,
    reused: r.reused,
  };
}

const notFound = (what: string, code: string): DomainError =>
  new DomainError("not-found", `${what} bulunamadı`, code);

export async function startDuePaymentHandler(
  deps: PayHandlerDeps & {
    readonly dues: DueReader;
    readonly partialEnabled: () => Promise<boolean>;
  },
  auth: CallableAuth | null | undefined,
  data: unknown,
): Promise<PayResult> {
  const ctx = requireAuth(auth);
  const o = asObject(data, "data");
  const dueId = asString(o["dueId"], "dueId", { max: 100 });
  const clientKey = asString(o["clientKey"], "clientKey", { min: 8, max: 100 });
  const requested =
    o["amountMinor"] === undefined ? undefined : asInt(o["amountMinor"], "amountMinor", { min: 1, max: 1_000_000_000 });

  const due = await deps.dues.get(dueId);
  if (!due || due.userId !== ctx.uid) throw notFound("Aidat borcu", "due_not_found");

  const nowMs = deps.nowMs();
  const decision = resolveDuePayment(due, nowMs, requested, await deps.partialEnabled());
  if (!decision.ok) {
    throw new DomainError("failed-precondition", "Bu borç için ödeme alınamıyor", `due_${decision.reason}`);
  }
  return toResult(
    await startPayment(deps.payments, deps.provider, {
      kind: "membership_due",
      refId: dueId,
      userId: ctx.uid,
      amount: { amountMinor: decision.amountMinor, currency: due.currency },
      clientKey,
      description: "Aidat ödemesi",
      nowMs,
      mode: deps.mode,
      newId: deps.newId,
    }),
  );
}

export async function startEventFeePaymentHandler(
  deps: PayHandlerDeps & { readonly registrations: RegistrationReader },
  auth: CallableAuth | null | undefined,
  data: unknown,
): Promise<PayResult> {
  const ctx = requireAuth(auth);
  const o = asObject(data, "data");
  const registrationId = asString(o["registrationId"], "registrationId", { max: 100 });
  const clientKey = asString(o["clientKey"], "clientKey", { min: 8, max: 100 });

  const reg = await deps.registrations.get(registrationId);
  if (!reg || reg.userId !== ctx.uid) throw notFound("Kayıt", "registration_not_found");
  const nowMs = deps.nowMs();
  if (reg.status !== "reserved") {
    throw new DomainError("failed-precondition", "Bu kayıt için ödeme alınamıyor", "registration_not_payable");
  }
  if (reg.reservedUntilMs === null || reg.reservedUntilMs <= nowMs) {
    throw new DomainError("failed-precondition", "Rezervasyon süresi doldu", "reservation_expired");
  }
  const fee = await deps.registrations.eventFee(reg.eventId);
  if (!fee) throw notFound("Etkinlik", "event_not_found");

  return toResult(
    await startPayment(deps.payments, deps.provider, {
      kind: "event_fee",
      refId: registrationId,
      userId: ctx.uid,
      amount: resolveEventFee(fee.feeMinor, fee.currency),
      clientKey,
      description: "Etkinlik ücreti",
      nowMs,
      mode: deps.mode,
      newId: deps.newId,
    }),
  );
}
