import { DomainError } from "../lib/errors";
import { EffectsDeps } from "../payments/effects";
import { IyzicoProvider, parseIyzicoWebhook, verifyIyzicoHppSignature } from "../payments/iyzico";
import { PipelineResult, handleProviderEvent } from "../payments/pipeline";
import { PaymentTxRunner } from "../payments/repo";

export interface IyzicoWebhookDeps {
  readonly secretKey: string;
  readonly provider: IyzicoProvider;
  readonly payments: PaymentTxRunner;
  readonly effects: EffectsDeps;
  readonly nowMs: () => number;
}

/**
 * HTTP yanıt kodları: 200 = tamam (iyzico tekrar denemesin), 400 = bozuk gövde, 401 = imza hatalı,
 * 500 = geçici hata (iyzico yeniden dener; ödeme ve etkiler idempotent olduğundan güvenli).
 * Ödeme sonucu webhook gövdesinden DEĞİL, iyzico'dan sunucu-sunucu sorgulanan sonuçtan alınır.
 */
export async function handleIyzicoWebhook(
  deps: IyzicoWebhookDeps,
  signatureHeader: string | undefined,
  body: unknown,
): Promise<{ httpStatus: 200 | 400 | 401 | 500; result?: PipelineResult }> {
  const payload = parseIyzicoWebhook(body);
  if (!payload) return { httpStatus: 400 };
  if (!verifyIyzicoHppSignature(deps.secretKey, payload, signatureHeader)) return { httpStatus: 401 };
  try {
    const r = await deps.provider.getResult(payload.token);
    if (r.status === "pending") return { httpStatus: 200 }; // henüz sonuçlanmamış; mutabakat bakar
    const result = await handleProviderEvent(deps.payments, deps.effects, {
      event: {
        providerRef: payload.token,
        status: r.status,
        amountMinor: r.amountMinor,
        currency: r.currency,
        ...(r.failureCode === undefined ? {} : { failureCode: r.failureCode }),
      },
      signatureValid: true, // imza yukarıda doğrulandı
      nowMs: deps.nowMs(),
    });
    return { httpStatus: result.effectsFailed ? 500 : 200, result };
  } catch (e) {
    if (e instanceof DomainError) return { httpStatus: 400 };
    return { httpStatus: 500 };
  }
}
