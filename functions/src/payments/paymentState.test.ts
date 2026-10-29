import { describe, expect, it } from "vitest";
import { PAYMENT_STATUSES, canTransition, countsAsCollected, decideWebhook } from "./paymentState";

describe("payment state machine", () => {
  it("geçerli geçişlere izin verir", () => {
    expect(canTransition("created", "pending")).toBe(true);
    expect(canTransition("pending", "succeeded")).toBe(true);
    expect(canTransition("succeeded", "partially_refunded")).toBe(true);
    expect(canTransition("partially_refunded", "refunded")).toBe(true);
  });

  it("geçersiz geçişleri reddeder", () => {
    expect(canTransition("created", "succeeded")).toBe(false);
    expect(canTransition("failed", "succeeded")).toBe(false);
    expect(canTransition("refunded", "succeeded")).toBe(false);
    expect(canTransition("cancelled", "pending")).toBe(false);
  });

  it("tekrarlanan webhook yok sayılır (idempotency)", () => {
    expect(decideWebhook("succeeded", "succeeded")).toEqual({
      action: "ignore",
      reason: "duplicate",
    });
  });

  it("başarısız ödeme sonradan başarılıya çevrilemez", () => {
    expect(decideWebhook("failed", "succeeded")).toEqual({
      action: "ignore",
      reason: "invalid_transition",
    });
  });

  it("bekleyen ödeme başarılı bildirimle uygulanır", () => {
    expect(decideWebhook("pending", "succeeded")).toEqual({
      action: "apply",
      next: "succeeded",
    });
  });

  it("webhook sırası bozulsa da başarılı ödeme geriye gitmez", () => {
    expect(decideWebhook("succeeded", "pending").action).toBe("ignore");
  });

  it("yalnızca doğrulanmış tahsilatlar toplama girer", () => {
    const collected = PAYMENT_STATUSES.filter(countsAsCollected);
    expect(collected).toEqual(["succeeded", "partially_refunded"]);
  });
});
