import { PaymentProvider } from "./provider";
import { PaymentTxRunner } from "./repo";
import { WebhookOutcome, processWebhook } from "./webhook";

export interface ReconcileOptions {
  readonly nowMs: number;
  /** Bu süreden eski `pending` ödemeler sorgulanır (webhook gecikmesine tolerans). */
  readonly olderThanMs: number;
  readonly batchSize: number;
  /** Bu süreden eski ve hâlâ pending olanlar iptal edilir (sağlayıcı da bilmiyorsa). */
  readonly expireAfterMs: number;
}

export interface ReconcileReport {
  readonly checked: number;
  readonly applied: number;
  readonly expired: number;
  readonly errors: number;
}

/**
 * Webhook gelmemiş/kaybolmuş ödemeleri sağlayıcıdan SUNUCU-SUNUCU sorgulayarak kapatır.
 * Sonuç, webhook ile AYNI idempotent yoldan (processWebhook) uygulanır; böylece
 * webhook ve mutabakat aynı anda çalışsa da çift işlem oluşmaz.
 * Simülasyon ödemeleri otomatik sonuçlandırılmaz (sağlayıcı pending dönerse dokunulmaz).
 */
export async function reconcilePending(
  runner: PaymentTxRunner,
  provider: PaymentProvider,
  opts: ReconcileOptions,
): Promise<ReconcileReport> {
  const stale = await runner.run((tx) =>
    tx.listPendingCreatedBefore(opts.nowMs - opts.olderThanMs, opts.batchSize),
  );

  let applied = 0;
  let expired = 0;
  let errors = 0;

  for (const p of stale) {
    if (!p.providerRef) continue;
    try {
      const result = provider.getResult
        ? await provider.getResult(p.providerRef)
        : { status: await provider.getStatus(p.providerRef), amountMinor: p.amountMinor, currency: p.currency };
      const status = result.status;
      if (status === "pending") {
        if (p.createdAtMs < opts.nowMs - opts.expireAfterMs) {
          const out: WebhookOutcome = await processWebhook(runner, {
            event: { providerRef: p.providerRef, status: "cancelled", amountMinor: null, currency: null },
            signatureValid: true, // sunucu-sunucu sorgusunun sonucu; harici imza gerekmez
            nowMs: opts.nowMs,
          });
          if (out.result === "applied") expired++;
        }
        continue;
      }
      const out = await processWebhook(runner, {
        event: {
          providerRef: p.providerRef,
          status,
          // Gerçek sağlayıcıda tutar `getResult` ile SAĞLAYICIDAN gelir (uyuşmazsa işaretlenir);
          // yalnızca simülasyonda kendi kaydımız kullanılır.
          amountMinor: result.amountMinor,
          currency: result.currency,
          ...(result.failureCode === undefined ? {} : { failureCode: result.failureCode }),
        },
        signatureValid: true,
        nowMs: opts.nowMs,
      });
      if (out.result === "applied") applied++;
    } catch {
      errors++; // tek ödemedeki hata diğerlerini durdurmaz; bir sonraki turda tekrar denenir
    }
  }
  return { checked: stale.length, applied, expired, errors };
}
