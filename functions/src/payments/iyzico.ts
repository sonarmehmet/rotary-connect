import { createHmac } from "node:crypto";
import { DomainError } from "../lib/errors";
import { constantTimeEqual } from "../lib/safeEqual";
import { CreateSessionInput, PaymentProvider, PaymentSession, ProviderResult } from "./provider";
import { PaymentStatus } from "./paymentState";

/**
 * iyzico Checkout Form (HPP) adaptörü. Ağ çağrısı `IyzicoHttp` portu üzerindendir (imzalı HTTP
 * istemcisi `firebase/iyzicoHttp.ts` içinde). DOĞRULANMAMIŞ: alan adları iyzico dokümanına göre
 * yazıldı ancak sandbox hesabıyla HİÇ denenmedi; ilk iş iyzico sandbox'ında uçtan uca denenmelidir.
 *
 * Güvenlik ilkesi: webhook gövdesine GÜVENİLMEZ. İmza doğrulandıktan sonra bile sonuç ve tutar
 * `getResult` ile iyzico'dan sunucu-sunucu yeniden sorgulanır (webhook gövdesinde tutar yok).
 */
export interface IyzicoHttp {
  post(path: string, body: Record<string, unknown>): Promise<Record<string, unknown>>;
}

export interface IyzicoBuyer {
  readonly id: string;
  readonly name: string;
  readonly surname: string;
  readonly email: string;
  readonly ip: string;
}

export interface IyzicoOptions {
  readonly http: IyzicoHttp;
  readonly callbackUrl: string;
  /** Bağlantı için alıcı bilgisi (iyzico zorunlu tutar). Misafir bağışta genel değerler kullanılabilir. */
  readonly buyerFor: (paymentId: string) => Promise<IyzicoBuyer>;
}

/** 12345 → "123.45" (iyzico fiyatı ondalıklı metin ister). Float kullanılmaz. */
export function minorToPrice(minor: number): string {
  if (!Number.isSafeInteger(minor) || minor < 0) throw new Error("Tutar geçersiz");
  const whole = Math.floor(minor / 100);
  const frac = String(minor % 100).padStart(2, "0");
  return `${whole}.${frac}`;
}

/** "123.45" / "123.4" / "123" → kuruş. Biçim bozuksa null. */
export function priceToMinor(price: unknown): number | null {
  const s = typeof price === "number" ? String(price) : typeof price === "string" ? price.trim() : "";
  const m = /^(\d{1,12})(?:\.(\d{1,2}))?$/.exec(s);
  if (!m) return null;
  return Number(m[1]) * 100 + Number((m[2] ?? "").padEnd(2, "0") || "0");
}

export interface IyzicoWebhookPayload {
  readonly iyziEventType: string;
  readonly iyziPaymentId: string;
  readonly token: string;
  readonly paymentConversationId: string;
  readonly status: string;
}

/** HPP (Checkout Form) imza dizgisi: secretKey + eventType + iyziPaymentId + token + conversationId + status. */
export function iyzicoHppSignature(secretKey: string, p: IyzicoWebhookPayload): string {
  const data = secretKey + p.iyziEventType + p.iyziPaymentId + p.token + p.paymentConversationId + p.status;
  return createHmac("sha256", secretKey).update(data, "utf8").digest("hex");
}

export function verifyIyzicoHppSignature(secretKey: string, p: IyzicoWebhookPayload, header: string | undefined): boolean {
  if (!header) return false;
  return constantTimeEqual(iyzicoHppSignature(secretKey, p), header.trim().toLowerCase());
}

const str = (v: unknown): string => (typeof v === "string" ? v : "");

/** Ham JSON gövdesinden gerekli alanları çıkarır; eksik/yanlış tipte alan varsa null (400). */
export function parseIyzicoWebhook(body: unknown): IyzicoWebhookPayload | null {
  if (typeof body !== "object" || body === null) return null;
  const o = body as Record<string, unknown>;
  const p: IyzicoWebhookPayload = {
    iyziEventType: str(o["iyziEventType"]),
    iyziPaymentId: str(o["iyziPaymentId"]),
    token: str(o["token"]),
    paymentConversationId: str(o["paymentConversationId"]),
    status: str(o["status"]),
  };
  return p.token === "" || p.status === "" ? null : p;
}

export class IyzicoProvider implements PaymentProvider {
  readonly name = "iyzico";
  constructor(private readonly o: IyzicoOptions) {}

  async createSession(input: CreateSessionInput): Promise<PaymentSession> {
    const price = minorToPrice(input.amount.amountMinor);
    const buyer = await this.o.buyerFor(input.paymentId);
    const res = await this.o.http.post("/payment/iyzipos/checkoutform/initialize/auth/ecom", {
      locale: "tr",
      conversationId: input.paymentId,
      price,
      paidPrice: price,
      currency: input.amount.currency,
      basketId: input.paymentId,
      paymentGroup: "PRODUCT",
      callbackUrl: this.o.callbackUrl,
      buyer: {
        id: buyer.id, name: buyer.name, surname: buyer.surname, email: buyer.email, ip: buyer.ip,
        identityNumber: "11111111111", registrationAddress: "-", city: "-", country: "Turkey",
      },
      shippingAddress: { contactName: buyer.name, city: "-", country: "Turkey", address: "-" },
      billingAddress: { contactName: buyer.name, city: "-", country: "Turkey", address: "-" },
      basketItems: [{ id: input.paymentId, name: input.description, category1: "Rotary", itemType: "VIRTUAL", price }],
    });
    const token = str(res["token"]);
    const url = str(res["paymentPageUrl"]);
    if (str(res["status"]) !== "success" || token === "" || url === "") {
      throw new DomainError("unavailable", "Ödeme sayfası şu an açılamıyor", "provider_unavailable");
    }
    return { providerRef: token, checkoutUrl: url, simulated: false };
  }

  async getResult(providerRef: string): Promise<ProviderResult> {
    const res = await this.o.http.post("/payment/iyzipos/checkoutform/auth/ecom/detail", {
      locale: "tr",
      token: providerRef,
    });
    if (str(res["status"]) !== "success") {
      // Sorgu başarısız: karar vermeyiz (pending), mutabakat sonra tekrar dener.
      return { status: "pending", amountMinor: null, currency: null };
    }
    const paid = str(res["paymentStatus"]);
    const status: PaymentStatus = paid === "SUCCESS" ? "succeeded" : paid === "FAILURE" ? "failed" : "pending";
    return {
      status,
      amountMinor: priceToMinor(res["paidPrice"]),
      currency: str(res["currency"]) || null,
      ...(status === "failed" ? { failureCode: str(res["errorCode"]) || "provider_failure" } : {}),
    };
  }

  /**
   * Kısmi/tam iade: önce ödeme ayrıntısından iyzico `paymentId` alınır, sonra tutar bazlı iade (v2).
   * DOĞRULANMAMIŞ uç nokta/alan adları; sandbox'ta denenmeli. `conversationId` = idempotencyKey.
   */
  async refund(providerRef: string, amountMinor: number, idempotencyKey: string): Promise<void> {
    const detail = await this.o.http.post("/payment/iyzipos/checkoutform/auth/ecom/detail", { locale: "tr", token: providerRef });
    const paymentId = str(detail["paymentId"]);
    if (str(detail["status"]) !== "success" || paymentId === "") throw new Error("iyzico ödeme ayrıntısı alınamadı");
    const res = await this.o.http.post("/v2/payment/refund", {
      locale: "tr",
      conversationId: idempotencyKey,
      paymentId,
      price: minorToPrice(amountMinor),
      ip: "85.34.78.112",
    });
    if (str(res["status"]) !== "success") throw new Error(`iyzico iadeyi reddetti: ${str(res["errorCode"])}`);
  }

  async getStatus(providerRef: string): Promise<PaymentStatus> {
    return (await this.getResult(providerRef)).status;
  }
}
