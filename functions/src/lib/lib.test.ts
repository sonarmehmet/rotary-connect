import { describe, expect, it } from "vitest";
import { assertValidMoney, moneyEquals } from "./money";
import { PermissionDeniedError, parseRole, requireRole } from "./roles";
import { SimulatedProvider } from "../payments/provider";

describe("money", () => {
  it("geçersiz tutarları reddeder", () => {
    expect(() => assertValidMoney({ amountMinor: 0, currency: "TRY" })).toThrow();
    expect(() => assertValidMoney({ amountMinor: 10.5, currency: "TRY" })).toThrow();
    expect(() => assertValidMoney({ amountMinor: -5, currency: "TRY" })).toThrow();
    expect(() => assertValidMoney({ amountMinor: 100, currency: "try" })).toThrow();
    expect(() => assertValidMoney({ amountMinor: 25000, currency: "TRY" })).not.toThrow();
  });

  it("tutar ve para birimi birebir eşleşmeli", () => {
    const a = { amountMinor: 25000, currency: "TRY" };
    expect(moneyEquals(a, { amountMinor: 25000, currency: "TRY" })).toBe(true);
    expect(moneyEquals(a, { amountMinor: 24999, currency: "TRY" })).toBe(false);
    expect(moneyEquals(a, { amountMinor: 25000, currency: "EUR" })).toBe(false);
  });
});

describe("roles", () => {
  it("bilinmeyen rol ziyaretçiye düşer", () => {
    expect(parseRole("root")).toBe("visitor");
    expect(parseRole(undefined)).toBe("visitor");
  });

  it("yetkisiz rol reddedilir", () => {
    expect(() => requireRole("content_manager", ["finance_manager"])).toThrow(
      PermissionDeniedError,
    );
    expect(requireRole("finance_manager", ["finance_manager", "system_admin"])).toBe(
      "finance_manager",
    );
  });
});

describe("SimulatedProvider", () => {
  it("simüle edilmiş oturum işaretlenir ve gerçek tahsilat sayılmaz", async () => {
    const provider = new SimulatedProvider();
    const session = await provider.createSession({
      paymentId: "p1",
      amount: { amountMinor: 25000, currency: "TRY" },
      description: "Test bağışı",
    });
    expect(session.simulated).toBe(true);
    expect(await provider.getStatus(session.providerRef)).toBe("pending");
    provider.simulateResult(session.providerRef, "succeeded");
    expect(await provider.getStatus(session.providerRef)).toBe("succeeded");
  });

  it("geçersiz tutarla oturum açılamaz", async () => {
    const provider = new SimulatedProvider();
    await expect(
      provider.createSession({
        paymentId: "p2",
        amount: { amountMinor: 0, currency: "TRY" },
        description: "x",
      }),
    ).rejects.toThrow();
  });
});
