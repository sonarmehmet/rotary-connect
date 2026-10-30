import { describe, expect, it } from "vitest";
import { MemoryPayments } from "../testing/memoryPayments";
import { aggregateByDay, campaignVerifiedTotal, istanbulDay } from "../reports/aggregates";
import { SimulatedProvider } from "./provider";
import { PaymentDoc } from "./repo";
import { reconcilePending } from "./reconcile";
import { startPayment } from "./startPayment";
import { processWebhook } from "./webhook";

const NOW = 1_800_000_000_000;
const MIN = 60_000;

function pay(over: Partial<PaymentDoc>): PaymentDoc {
  return {
    id: "p",
    kind: "donation",
    refId: "c1",
    userId: "u",
    amountMinor: 10_000,
    currency: "TRY",
    status: "succeeded",
    provider: "iyzico",
    providerRef: "R",
    simulated: false,
    idempotencyKey: "k",
    manual: false,
    recordedBy: null,
    note: null,
    refundedMinor: 0,
    createdAtMs: NOW,
    updatedAtMs: NOW,
    succeededAtMs: NOW,
    failureCode: null,
    flag: null,
    ...over,
  };
}

describe("istanbulDay", () => {
  it("UTC+3'e göre gün keser", () => {
    // 2026-01-01 21:30 UTC = 2026-01-02 00:30 İstanbul
    expect(istanbulDay(Date.UTC(2026, 0, 1, 21, 30))).toBe("2026-01-02");
    expect(istanbulDay(Date.UTC(2026, 0, 1, 20, 59))).toBe("2026-01-01");
  });
});

describe("rapor toplamları", () => {
  it("bağış, aidat ve etkinlik ayrı satırlardır", () => {
    const rows = aggregateByDay([
      pay({ id: "1", kind: "donation", amountMinor: 1000 }),
      pay({ id: "2", kind: "membership_due", amountMinor: 5000 }),
      pay({ id: "3", kind: "event_fee", amountMinor: 700 }),
    ]);
    expect(rows.map((r) => [r.kind, r.collectedMinor])).toEqual([
      ["donation", 1000],
      ["event_fee", 700],
      ["membership_due", 5000],
    ]);
  });

  it("simülasyon, bekleyen, başarısız ve şüpheli ödemeler sayılmaz", () => {
    const rows = aggregateByDay([
      pay({ id: "1", simulated: true }),
      pay({ id: "2", status: "pending", succeededAtMs: null }),
      pay({ id: "3", status: "failed", succeededAtMs: null }),
      pay({ id: "4", flag: "amount_mismatch" }),
      pay({ id: "5", amountMinor: 2500 }),
    ]);
    expect(rows.length).toBe(1);
    expect(rows[0]?.collectedMinor).toBe(2500);
    expect(rows[0]?.count).toBe(1);
  });

  it("iade brütten ayrı gösterilir, net düşülür; manuel ayrı izlenir", () => {
    const [row] = aggregateByDay([
      pay({ id: "1", amountMinor: 10_000, refundedMinor: 4000, status: "partially_refunded" }),
      pay({ id: "2", amountMinor: 3000, manual: true, provider: "manual" }),
    ]);
    expect(row?.collectedMinor).toBe(13_000);
    expect(row?.refundedMinor).toBe(4000);
    expect(row?.netMinor).toBe(9000);
    expect(row?.manualMinor).toBe(3000);
  });

  it("tamamen iade edilen ödeme brüt/iade olarak görünür, net 0", () => {
    const [row] = aggregateByDay([pay({ status: "refunded", refundedMinor: 10_000 })]);
    expect(row?.netMinor).toBe(0);
  });

  it("kampanya toplamı yalnızca doğrulanmış bağışlar, iade düşülmüş, başka kampanya hariç", () => {
    const total = campaignVerifiedTotal(
      [
        pay({ id: "1", amountMinor: 10_000 }),
        pay({ id: "2", amountMinor: 5000, refundedMinor: 1000, status: "partially_refunded" }),
        pay({ id: "3", refId: "other", amountMinor: 99_999 }),
        pay({ id: "4", status: "pending", succeededAtMs: null }),
        pay({ id: "5", simulated: true, amountMinor: 77_777 }),
        pay({ id: "6", kind: "membership_due", amountMinor: 88_888 }),
      ],
      "c1",
    );
    expect(total).toBe(14_000);
  });
});

describe("reconcilePending", () => {
  const opts = (nowMs: number) => ({
    nowMs,
    olderThanMs: 10 * MIN,
    batchSize: 50,
    expireAfterMs: 60 * MIN,
  });

  async function seed() {
    const db = new MemoryPayments();
    const provider = new SimulatedProvider();
    const r = await startPayment(db, provider, {
      kind: "donation",
      refId: "c1",
      userId: "u1",
      amount: { amountMinor: 25_000, currency: "TRY" },
      clientKey: "client-key-1",
      description: "t",
      nowMs: NOW,
      mode: "simulation",
      newId: () => "x",
    });
    return { db, provider, ref: r.payment.providerRef as string };
  }

  it("taze ödemelere dokunmaz", async () => {
    const { db, provider } = await seed();
    const rep = await reconcilePending(db, provider, opts(NOW + 5 * MIN));
    expect(rep.checked).toBe(0);
  });

  it("webhook'u kaçırılmış başarılı ödemeyi kapatır", async () => {
    const { db, provider, ref } = await seed();
    provider.simulateResult(ref, "succeeded");
    const rep = await reconcilePending(db, provider, opts(NOW + 15 * MIN));
    expect(rep).toEqual({ checked: 1, applied: 1, expired: 0, errors: 0 });
    expect(db.all()[0]?.status).toBe("succeeded");
  });

  it("webhook ile mutabakat art arda çalışsa da çift işlem olmaz", async () => {
    const { db, provider, ref } = await seed();
    provider.simulateResult(ref, "succeeded");
    await processWebhook(db, {
      event: { providerRef: ref, status: "succeeded", amountMinor: 25_000, currency: "TRY" },
      signatureValid: true,
      nowMs: NOW + 1,
    });
    const rep = await reconcilePending(db, provider, opts(NOW + 15 * MIN));
    expect(rep.checked).toBe(0); // artık pending değil
    expect(db.all()[0]?.status).toBe("succeeded");
  });

  it("sağlayıcı da hâlâ pending diyorsa uzun süre sonra iptal eder", async () => {
    const { db, provider } = await seed();
    const early = await reconcilePending(db, provider, opts(NOW + 30 * MIN));
    expect(early.expired).toBe(0);
    expect(db.all()[0]?.status).toBe("pending");
    const late = await reconcilePending(db, provider, opts(NOW + 90 * MIN));
    expect(late.expired).toBe(1);
    expect(db.all()[0]?.status).toBe("cancelled");
  });

  it("sağlayıcı hatası diğer ödemeleri durdurmaz", async () => {
    const { db, provider, ref } = await seed();
    await startPayment(db, provider, {
      kind: "donation",
      refId: "c1",
      userId: "u2",
      amount: { amountMinor: 5000, currency: "TRY" },
      clientKey: "client-key-2",
      description: "t",
      nowMs: NOW,
      mode: "simulation",
      newId: () => "y",
    });
    provider.simulateResult(ref, "succeeded");
    const flaky = {
      name: "flaky",
      createSession: provider.createSession.bind(provider),
      getStatus: async (r: string) => {
        if (r !== ref) throw new Error("ağ hatası");
        return provider.getStatus(r);
      },
    };
    const rep = await reconcilePending(db, flaky, opts(NOW + 15 * MIN));
    expect(rep.checked).toBe(2);
    expect(rep.applied).toBe(1);
    expect(rep.errors).toBe(1);
  });
});
