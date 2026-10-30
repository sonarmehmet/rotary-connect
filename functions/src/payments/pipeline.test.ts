import { describe, expect, it } from "vitest";
import { EventRegistrationService } from "../events/service";
import { NotificationItem } from "../notifications/notifications";
import { MemoryEffects } from "../testing/memoryEffects";
import { MemoryPayments } from "../testing/memoryPayments";
import { MemoryStore } from "../testing/memoryStore";
import { EffectsDeps } from "./effects";
import { handleProviderEvent, sweepEffects } from "./pipeline";
import { SimulatedProvider } from "./provider";
import { startPayment } from "./startPayment";

const NOW = 1_800_000_000_000;
const DAY = 86_400_000;

async function setup() {
  const payments = new MemoryPayments();
  const fx = new MemoryEffects();
  const notes = new Map<string, NotificationItem>();
  const deps: EffectsDeps = {
    runner: fx,
    events: new EventRegistrationService(new MemoryStore([])),
    notifications: { createIfAbsent: async (items) => void items.forEach((i) => notes.set(i.id, i)) },
    refunds: { request: async () => undefined },
    nowMs: () => NOW,
  };
  fx.dues.set("due1", {
    id: "due1", userId: "u1", currency: "TRY", amountMinor: 100_000, paidMinor: 0, dueDateMs: NOW + DAY,
    cancelled: false, refunded: false, allowPartial: false, status: "unpaid",
  });
  const started = await startPayment(payments, new SimulatedProvider(), {
    kind: "membership_due", refId: "due1", userId: "u1", amount: { amountMinor: 100_000, currency: "TRY" },
    clientKey: "client-key-1", description: "Aidat", nowMs: NOW, mode: "simulation", newId: () => "x1",
  });
  return { payments, fx, notes, deps, payment: started.payment };
}

const input = (ref: string, amountMinor = 100_000) => ({
  event: { providerRef: ref, status: "succeeded" as const, amountMinor, currency: "TRY" },
  signatureValid: true,
  nowMs: NOW,
});

describe("webhook → etkiler akışı", () => {
  it("başarılı bildirim ödemeyi kapatır ve borca yansır; tekrar bildirim etkisizdir", async () => {
    const { payments, fx, deps, payment } = await setup();
    const ref = payment.providerRef as string;
    const first = await handleProviderEvent(payments, deps, input(ref));
    expect(first.webhook.result).toBe("applied");
    expect(first.effectsFailed).toBe(false);
    expect(fx.dues.get("due1")?.status).toBe("paid");
    const second = await handleProviderEvent(payments, deps, input(ref));
    expect(second.webhook.result).toBe("ignored");
    expect(fx.dues.get("due1")?.paidMinor).toBe(100_000);
    expect(fx.duePayments.length).toBe(1);
  });

  it("tutar uyuşmazlığı etki uygulamaz", async () => {
    const { payments, fx, deps, payment } = await setup();
    const out = await handleProviderEvent(payments, deps, input(payment.providerRef as string, 1));
    expect(out.webhook.result).toBe("flagged");
    expect(out.effects.length).toBe(0);
    expect(fx.dues.get("due1")?.paidMinor).toBe(0);
  });

  it("etki adımı hata verirse ödeme korunur, effectsFailed döner ve tarama düzeltir", async () => {
    const { payments, fx, deps, payment } = await setup();
    const broken: EffectsDeps = { ...deps, runner: { run: async () => { throw new Error("db down"); } } };
    const out = await handleProviderEvent(payments, broken, input(payment.providerRef as string));
    expect(out.effectsFailed).toBe(true);
    expect(payments.all()[0]?.status).toBe("succeeded");
    expect(fx.dues.get("due1")?.paidMinor).toBe(0);

    const source = { listSucceededSince: async () => payments.all().filter((p) => p.status === "succeeded") };
    const r1 = await sweepEffects(source, deps, 0, 50);
    expect(r1).toEqual({ checked: 1, applied: 1, errors: 0 });
    expect(fx.dues.get("due1")?.status).toBe("paid");
    const r2 = await sweepEffects(source, deps, 0, 50);
    expect(r2).toEqual({ checked: 1, applied: 0, errors: 0 });
    expect(fx.duePayments.length).toBe(1);
  });
});
