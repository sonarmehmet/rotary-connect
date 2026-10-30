import { defineSecret, defineString } from "firebase-functions/params";
import { IyzicoProvider } from "../payments/iyzico";
import { PaymentProvider, SimulatedProvider } from "../payments/provider";
import { iyzicoHttp } from "./iyzicoHttp";

/** Ödeme yapılandırması: main.ts ve callables.ts ortak kullanır. DOĞRULANMAMIŞ (SDK derlenmedi). */
export const PAYMENT_MODE = defineString("PAYMENT_MODE", { default: "simulation" });
export const IYZICO_BASE_URL = defineString("IYZICO_BASE_URL", { default: "https://sandbox-api.iyzipay.com" });
export const PUBLIC_BASE_URL = defineString("PUBLIC_BASE_URL", { default: "https://example.invalid" });
export const IYZICO_API_KEY = defineSecret("IYZICO_API_KEY");
export const IYZICO_SECRET_KEY = defineSecret("IYZICO_SECRET_KEY");
export const SECRETS = [IYZICO_API_KEY, IYZICO_SECRET_KEY];

export const isLive = (): boolean => PAYMENT_MODE.value() === "live";

export function iyzico(): IyzicoProvider {
  return new IyzicoProvider({
    http: iyzicoHttp({ baseUrl: IYZICO_BASE_URL.value(), apiKey: IYZICO_API_KEY.value(), secretKey: IYZICO_SECRET_KEY.value() }),
    callbackUrl: `${PUBLIC_BASE_URL.value()}/payment-return`,
    buyerFor: async (paymentId) => ({ id: paymentId, name: "Rotary", surname: "Bağışçı", email: "noreply@rotary.invalid", ip: "85.34.78.112" }),
  });
}

const simulated = new SimulatedProvider();
export const activeProvider = (): PaymentProvider => (isLive() ? iyzico() : simulated);
