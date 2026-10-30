import { EffectOutcome, EffectsDeps, applyEffects } from "./effects";
import { PaymentDoc, PaymentTxRunner } from "./repo";
import { WebhookInput, WebhookOutcome, processWebhook } from "./webhook";

/**
 * Webhook → ödeme durumu → iş kayıtlarına etkiler, tek akışta.
 * Ödeme durumu ÖNCE kalıcı yazılır (processWebhook kendi transaction'ında); etkiler ayrı adımdır.
 * Etki adımı hata verirse ödeme `succeeded` kalır ve HATA yutulmaz: `effectsFailed` döner,
 * çağıran (HTTP işleyici) sağlayıcıya yeniden deneme isteyen yanıt verebilir ya da `sweepEffects`
 * sonradan yakalar. Etkiler idempotent olduğundan tekrar güvenlidir.
 */
export interface PipelineResult {
  readonly webhook: WebhookOutcome;
  readonly effects: readonly EffectOutcome[];
  readonly effectsFailed: boolean;
}

export async function handleProviderEvent(
  runner: PaymentTxRunner,
  deps: EffectsDeps,
  input: WebhookInput,
): Promise<PipelineResult> {
  const webhook = await processWebhook(runner, input);
  if (webhook.result !== "applied") return { webhook, effects: [], effectsFailed: false };
  try {
    return { webhook, effects: await applyEffects(deps, webhook.effects), effectsFailed: false };
  } catch {
    return { webhook, effects: [], effectsFailed: true };
  }
}

/** Taramanın ihtiyacı: etkisi uygulanmamış olabilecek başarılı ödemeleri listeleyen kaynak. */
export interface SucceededPaymentSource {
  listSucceededSince(sinceMs: number, limit: number): Promise<readonly PaymentDoc[]>;
}

export interface SweepReport {
  readonly checked: number;
  readonly applied: number;
  readonly errors: number;
}

/**
 * Zamanlanmış tarama: son dönemde başarılı olan ödemelerin etkilerini yeniden uygular.
 * İşaretçiler sayesinde zaten uygulananlar `already_applied` döner (yan etki yok).
 * Simülasyon ödemeleri de taranır (kampanya toplamına girmemeleri effects.ts'de güvence altında).
 */
export async function sweepEffects(
  source: SucceededPaymentSource,
  deps: EffectsDeps,
  sinceMs: number,
  limit: number,
): Promise<SweepReport> {
  const payments = await source.listSucceededSince(sinceMs, limit);
  let applied = 0;
  let errors = 0;
  for (const p of payments) {
    try {
      const [out] = await applyEffects(deps, [{ type: "collected", payment: p }]);
      if (out && out.result === "applied") applied++;
    } catch {
      errors++;
    }
  }
  return { checked: payments.length, applied, errors };
}
