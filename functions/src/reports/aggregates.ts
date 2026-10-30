import { PaymentDoc, PaymentKindWire } from "../payments/repo";

/**
 * Rapor toplamları: bağış, aidat ve etkinlik geliri AYRI satırlardır, asla birleştirilmez.
 * Kurallar:
 * - Yalnızca gerçekten tahsil edilmiş (succeeded / partially_refunded) ödemeler sayılır.
 * - SİMÜLASYON ödemeleri hiçbir rapora girmez.
 * - Şüpheli (flag) ödemeler sayılmaz.
 * - İadeler brüt tahsilattan ayrı gösterilir; net = tahsilat − iade.
 * - Günler Europe/Istanbul (UTC+3, yaz saati uygulaması yok) takvimine göre kesilir.
 */
const ISTANBUL_OFFSET_MS = 3 * 60 * 60 * 1000;

export function istanbulDay(ms: number): string {
  const d = new Date(ms + ISTANBUL_OFFSET_MS);
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, "0");
  const day = String(d.getUTCDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

export interface AggregateRow {
  readonly day: string;
  readonly kind: PaymentKindWire;
  readonly currency: string;
  readonly collectedMinor: number;
  readonly refundedMinor: number;
  readonly netMinor: number;
  readonly manualMinor: number;
  readonly count: number;
}

export function countsInReports(p: PaymentDoc): boolean {
  return (
    (p.status === "succeeded" || p.status === "partially_refunded" || p.status === "refunded") &&
    !p.simulated &&
    p.flag === null &&
    p.succeededAtMs !== null
  );
}

export function aggregateByDay(payments: readonly PaymentDoc[]): AggregateRow[] {
  const rows = new Map<string, AggregateRow>();
  for (const p of payments) {
    if (!countsInReports(p) || p.succeededAtMs === null) continue;
    const day = istanbulDay(p.succeededAtMs);
    const key = `${day}|${p.kind}|${p.currency}`;
    const cur =
      rows.get(key) ??
      ({ day, kind: p.kind, currency: p.currency, collectedMinor: 0, refundedMinor: 0, netMinor: 0, manualMinor: 0, count: 0 } as AggregateRow);
    const collectedMinor = cur.collectedMinor + p.amountMinor;
    const refundedMinor = cur.refundedMinor + p.refundedMinor;
    rows.set(key, {
      ...cur,
      collectedMinor,
      refundedMinor,
      netMinor: collectedMinor - refundedMinor,
      manualMinor: cur.manualMinor + (p.manual ? p.amountMinor : 0),
      count: cur.count + 1,
    });
  }
  return [...rows.values()].sort((a, b) =>
    a.day === b.day ? a.kind.localeCompare(b.kind) : a.day.localeCompare(b.day),
  );
}

/** Kampanya "toplanan" tutarı: yalnızca doğrulanmış bağışlar, iadeler düşülmüş. */
export function campaignVerifiedTotal(payments: readonly PaymentDoc[], campaignId: string): number {
  return payments
    .filter((p) => p.kind === "donation" && p.refId === campaignId && countsInReports(p))
    .reduce((sum, p) => sum + p.amountMinor - p.refundedMinor, 0);
}
