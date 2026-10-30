import { describe, expect, it } from "vitest";
import { buildAuditEntry, redact } from "./audit/audit";
import { DueDoc, applyPayment, deriveDueStatus, remainingMinor, resolveDuePayment } from "./dues/dues";
import { DomainError } from "./lib/errors";
import { resolveDonationAmount, resolveEventFee } from "./payments/amounts";
import { buildManualPayment } from "./payments/manual";
import { planRefund } from "./payments/refunds";

const DAY = 86_400_000;
const NOW = 1_800_000_000_000;

function due(over: Partial<DueDoc> = {}): DueDoc {
  return {
    amountMinor: 120_000,
    paidMinor: 0,
    dueDateMs: NOW + 10 * DAY,
    cancelled: false,
    refunded: false,
    allowPartial: false,
    ...over,
  };
}

function reason(fn: () => unknown): string | undefined {
  try {
    fn();
    return undefined;
  } catch (e) {
    return e instanceof DomainError ? (e.reason ?? e.code) : "other";
  }
}

describe("aidat durumu", () => {
  it("türetilen durumlar", () => {
    expect(deriveDueStatus(due(), NOW)).toBe("unpaid");
    expect(deriveDueStatus(due({ paidMinor: 1000 }), NOW)).toBe("partially_paid");
    expect(deriveDueStatus(due({ paidMinor: 120_000 }), NOW)).toBe("paid");
    expect(deriveDueStatus(due({ dueDateMs: NOW - DAY }), NOW)).toBe("overdue");
    expect(deriveDueStatus(due({ cancelled: true }), NOW)).toBe("cancelled");
    expect(deriveDueStatus(due({ refunded: true }), NOW)).toBe("refunded");
  });

  it("ödenmiş borç gecikmiş sayılmaz", () => {
    expect(deriveDueStatus(due({ paidMinor: 120_000, dueDateMs: NOW - DAY }), NOW)).toBe("paid");
  });
});

describe("aidat ödemesi", () => {
  it("tutar verilmezse kalan tutarın tamamı", () => {
    expect(resolveDuePayment(due({ paidMinor: 20_000 }), NOW, undefined, true)).toEqual({
      ok: true,
      amountMinor: 100_000,
    });
  });

  it("kısmi ödeme: borçta VE ayarda açıksa", () => {
    expect(resolveDuePayment(due({ allowPartial: true }), NOW, 50_000, true)).toEqual({
      ok: true,
      amountMinor: 50_000,
    });
    expect(resolveDuePayment(due({ allowPartial: true }), NOW, 50_000, false)).toEqual({
      ok: false,
      reason: "partial_not_allowed",
    });
    expect(resolveDuePayment(due({ allowPartial: false }), NOW, 50_000, true)).toEqual({
      ok: false,
      reason: "partial_not_allowed",
    });
  });

  it("geçersiz ve aşan tutarlar reddedilir", () => {
    const d = due({ allowPartial: true });
    expect(resolveDuePayment(d, NOW, 0, true)).toEqual({ ok: false, reason: "invalid_amount" });
    expect(resolveDuePayment(d, NOW, 10.5, true)).toEqual({ ok: false, reason: "invalid_amount" });
    expect(resolveDuePayment(d, NOW, 999_999, true)).toEqual({
      ok: false,
      reason: "exceeds_remaining",
    });
  });

  it("ödenmiş/iptal borç ödenemez", () => {
    expect(resolveDuePayment(due({ paidMinor: 120_000 }), NOW, undefined, true).ok).toBe(false);
    expect(resolveDuePayment(due({ cancelled: true }), NOW, undefined, true).ok).toBe(false);
  });

  it("gecikmiş borç yine ödenebilir", () => {
    expect(resolveDuePayment(due({ dueDateMs: NOW - DAY }), NOW, undefined, true).ok).toBe(true);
  });

  it("ödeme uygulanır; aşırı ödeme engellenir", () => {
    const paid = applyPayment(due(), 120_000);
    expect(remainingMinor(paid)).toBe(0);
    expect(() => applyPayment(due({ paidMinor: 100_000 }), 30_000)).toThrow();
    expect(() => applyPayment(due(), 0)).toThrow();
  });
});

describe("iade planı", () => {
  const base = { status: "succeeded" as const, amountMinor: 100_000, refundedMinor: 0, simulated: false };

  it("tam iade", () => {
    expect(planRefund(base)).toEqual({
      refundMinor: 100_000,
      newRefundedMinor: 100_000,
      nextStatus: "refunded",
    });
  });

  it("kısmi iade sonra kalanı", () => {
    const first = planRefund(base, 30_000);
    expect(first.nextStatus).toBe("partially_refunded");
    const second = planRefund(
      { ...base, status: "partially_refunded", refundedMinor: first.newRefundedMinor },
      70_000,
    );
    expect(second.nextStatus).toBe("refunded");
  });

  it("aşan, sıfır veya kesirli iade reddedilir", () => {
    expect(reason(() => planRefund(base, 100_001))).toBe("exceeds_remaining");
    expect(reason(() => planRefund(base, 0))).toBe("invalid_amount");
    expect(reason(() => planRefund(base, 10.5))).toBe("invalid_amount");
  });

  it("tahsil edilmemiş veya tamamen iade edilmiş ödeme iade edilemez", () => {
    for (const status of ["created", "pending", "failed", "cancelled", "refunded"] as const) {
      expect(reason(() => planRefund({ ...base, status }))).toBe("not_refundable");
    }
  });
});

describe("ödeme tutarını sunucu belirler", () => {
  it("bağış sınırları", () => {
    expect(resolveDonationAmount(25_000)).toEqual({ amountMinor: 25_000, currency: "TRY" });
    expect(reason(() => resolveDonationAmount(99))).toBe("below_minimum");
    expect(reason(() => resolveDonationAmount(10_000_001))).toBe("above_maximum");
    expect(reason(() => resolveDonationAmount("250"))).toBe("invalid_amount");
    expect(reason(() => resolveDonationAmount(250.5))).toBe("invalid_amount");
    expect(reason(() => resolveDonationAmount(NaN))).toBe("invalid_amount");
  });

  it("etkinlik ücreti kayıttan gelir; ücretsizde ödeme yok", () => {
    expect(resolveEventFee(50_000, "TRY")).toEqual({ amountMinor: 50_000, currency: "TRY" });
    expect(reason(() => resolveEventFee(0, "TRY"))).toBe("free_event");
  });
});

describe("manuel ödeme", () => {
  const ok = {
    actorRole: "finance_manager",
    actorId: "fin1",
    kind: "membership_due" as const,
    refId: "due1",
    amountMinor: 120_000,
    currency: "TRY",
    receivedAtMs: NOW - DAY,
    note: "Elden teslim alındı",
    nowMs: NOW,
  };

  it("finans yöneticisi kaydeder; manuel ve gerçek (simüle değil) işaretlenir", () => {
    const rec = buildManualPayment(ok);
    expect(rec.manual).toBe(true);
    expect(rec.provider).toBe("manual");
    expect(rec.recordedBy).toBe("fin1");
    expect(rec.status).toBe("succeeded");
  });

  it("aynı ödeme aynı gün aynı anahtarı üretir (mükerrer engeli)", () => {
    expect(buildManualPayment(ok).idempotencyKey).toBe(buildManualPayment(ok).idempotencyKey);
    expect(buildManualPayment({ ...ok, amountMinor: 5000 }).idempotencyKey).not.toBe(
      buildManualPayment(ok).idempotencyKey,
    );
  });

  it("diğer roller kaydedemez (sistem yöneticisi dahil)", () => {
    for (const role of ["content_manager", "club_member", "system_admin", "visitor", undefined]) {
      expect(() => buildManualPayment({ ...ok, actorRole: role })).toThrow();
    }
  });

  it("açıklama zorunlu, tarih gelecekte olamaz, tutar geçerli olmalı", () => {
    expect(reason(() => buildManualPayment({ ...ok, note: "  " }))).toBe("note_required");
    expect(reason(() => buildManualPayment({ ...ok, receivedAtMs: NOW + DAY }))).toBe("future_date");
    expect(() => buildManualPayment({ ...ok, amountMinor: 0 })).toThrow();
  });
});

describe("denetim kaydı", () => {
  it("hassas alanlar iç içe de olsa temizlenir", () => {
    const cleaned = redact({
      amountMinor: 100,
      donor: { name: "Ali", email: "a@b.c" },
      meta: { email: "x@y.z", ok: 1, list: [{ phone: "555", keep: true }] },
    });
    expect(cleaned).toEqual({ amountMinor: 100, meta: { ok: 1, list: [{ keep: true }] } });
  });

  it("kayıt oluşturur ve before/after'ı temizler", () => {
    const e = buildAuditEntry({
      actorId: "fin1",
      actorRole: "finance_manager",
      action: "refund.issue",
      targetType: "payment",
      targetId: "p1",
      before: { refundedMinor: 0 },
      after: { refundedMinor: 500, donor: { email: "a@b.c" } },
      nowMs: NOW,
    });
    expect(e.after).toEqual({ refundedMinor: 500 });
    expect(e.before).toEqual({ refundedMinor: 0 });
    const noBefore = buildAuditEntry({ ...e, before: null, nowMs: NOW });
    expect(noBefore.before).toBe(null);
  });
});
