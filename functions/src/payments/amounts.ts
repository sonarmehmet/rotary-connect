import { DomainError } from "../lib/errors";
import { Money } from "../lib/money";

/**
 * Ödeme tutarını SUNUCUDA belirler. İstemci yalnızca bağışta tutar önerebilir
 * (alt/üst sınır doğrulanır); aidat ve etkinlik tutarı kayıtlardan okunur.
 */
export interface DonationLimits {
  readonly minMinor: number;
  readonly maxMinor: number;
}

export const DEFAULT_DONATION_LIMITS: DonationLimits = {
  minMinor: 100, // 1 ₺
  maxMinor: 100_000_00, // 100.000 ₺ (ayarlardan değiştirilebilir)
};

export function resolveDonationAmount(
  requestedMinor: unknown,
  limits: DonationLimits = DEFAULT_DONATION_LIMITS,
  currency = "TRY",
): Money {
  if (typeof requestedMinor !== "number" || !Number.isSafeInteger(requestedMinor)) {
    throw new DomainError("invalid-argument", "Bağış tutarı geçersiz", "invalid_amount");
  }
  if (requestedMinor < limits.minMinor) {
    throw new DomainError("invalid-argument", "Bağış tutarı çok düşük", "below_minimum");
  }
  if (requestedMinor > limits.maxMinor) {
    throw new DomainError("invalid-argument", "Bağış tutarı izin verilen üst sınırı aşıyor", "above_maximum");
  }
  return { amountMinor: requestedMinor, currency };
}

/** Etkinlik ücreti: istemci tutar gönderse de etkinlik kaydındaki ücret esas alınır. */
export function resolveEventFee(feeMinor: number, currency: string): Money {
  if (feeMinor <= 0) {
    throw new DomainError("failed-precondition", "Ücretsiz etkinlik için ödeme gerekmez", "free_event");
  }
  return { amountMinor: feeMinor, currency };
}
