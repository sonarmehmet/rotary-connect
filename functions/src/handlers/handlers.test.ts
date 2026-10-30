import { describe, expect, it } from "vitest";
import { AuditEntry } from "../audit/audit";
import { EventDoc } from "../events/capacity";
import { EventRegistrationService } from "../events/service";
import { DomainError } from "../lib/errors";
import { PermissionDeniedError } from "../lib/roles";
import { SimulatedProvider } from "../payments/provider";
import { MemoryPayments } from "../testing/memoryPayments";
import { MemoryStore } from "../testing/memoryStore";
import { INTERNAL_MESSAGE, toCallableError } from "./callableError";
import {
  CallableAuth,
  CampaignInfo,
  PendingDonation,
  cancelRegistrationHandler,
  recordManualPaymentHandler,
  requireAuth,
  reserveEventSpotHandler,
  startDonationHandler,
} from "./handlers";
import { asEmail, asInt, asString } from "./validate";

const NOW = 1_800_000_000_000;
const DAY = 86_400_000;

const authAs = (uid: string, role?: string): CallableAuth => ({
  uid,
  token: role === undefined ? {} : { role },
});

async function failure(p: Promise<unknown>): Promise<string> {
  try {
    await p;
    return "no-error";
  } catch (e) {
    const c = toCallableError(e);
    return `${c.code}:${c.reason ?? ""}`;
  }
}

function failureSync(fn: () => unknown): string {
  try {
    fn();
    return "no-error";
  } catch (e) {
    const c = toCallableError(e);
    return `${c.code}:${c.reason ?? ""}`;
  }
}

describe("toCallableError", () => {
  it("DomainError ve PermissionDeniedError eşlenir", () => {
    expect(toCallableError(new DomainError("failed-precondition", "dolu", "sold_out"))).toEqual({
      code: "failed-precondition",
      message: "dolu",
      reason: "sold_out",
    });
    expect(toCallableError(new PermissionDeniedError()).code).toBe("permission-denied");
  });

  it("beklenmeyen hata ayrıntı sızdırmaz", () => {
    const out = toCallableError(new Error("db şifresi=hunter2 /var/secret"));
    expect(out).toEqual({ code: "internal", message: INTERNAL_MESSAGE, reason: null });
    expect(JSON.stringify(out).includes("hunter2")).toBe(false);
    expect(toCallableError("düz metin").code).toBe("internal");
  });
});

describe("doğrulayıcılar", () => {
  it("dize kırpılır; kontrol karakteri, boş ve çok uzun reddedilir", () => {
    expect(asString("  Ali  ", "name")).toBe("Ali");
    expect(failureSync(() => asString("A\u0000B", "name"))).toBe("invalid-argument:invalid_name");
    expect(failureSync(() => asString("   ", "name"))).toBe("invalid-argument:invalid_name");
    expect(failureSync(() => asString("x".repeat(201), "name"))).toBe("invalid-argument:invalid_name");
    expect(failureSync(() => asString(42, "name"))).toBe("invalid-argument:invalid_name");
  });

  it("e-posta küçük harfe çevrilir, geçersizler reddedilir", () => {
    expect(asEmail(" Ali@Example.COM ")).toBe("ali@example.com");
    for (const bad of ["ali", "a@b", "a b@c.com", "@x.com", 5, null]) {
      expect(failureSync(() => asEmail(bad))).toBe("invalid-argument:invalid_email");
    }
  });

  it("tam sayı: kesirli, NaN, metin ve aralık dışı reddedilir", () => {
    expect(asInt(5, "n", { min: 1, max: 10 })).toBe(5);
    for (const bad of [5.5, NaN, Infinity, "5", 0, 11, null]) {
      expect(failureSync(() => asInt(bad, "n", { min: 1, max: 10 }))).toBe("invalid-argument:invalid_n");
    }
  });
});

describe("requireAuth", () => {
  it("oturum yoksa unauthenticated", () => {
    expect(failureSync(() => requireAuth(null))).toBe("unauthenticated:login_required");
    expect(failureSync(() => requireAuth(undefined))).toBe("unauthenticated:login_required");
    expect(failureSync(() => requireAuth({ uid: "", token: {} }))).toBe("unauthenticated:login_required");
  });

  it("rol claim'i yoksa registered_user, bilinmeyen claim visitor", () => {
    expect(requireAuth(authAs("u1")).role).toBe("registered_user");
    expect(requireAuth(authAs("u1", "finance_manager")).role).toBe("finance_manager");
    expect(requireAuth(authAs("u1", "root")).role).toBe("visitor");
  });
});

function eventDoc(over: Partial<EventDoc> = {}): EventDoc {
  return {
    id: "ev1",
    capacity: 2,
    reservedCount: 0,
    confirmedCount: 0,
    waitlistEnabled: true,
    status: "published",
    registrationDeadlineMs: NOW + DAY,
    feeMinor: 50_000,
    currency: "TRY",
    ...over,
  };
}

describe("etkinlik işleyicileri", () => {
  function setup() {
    const store = new MemoryStore([eventDoc()]);
    const deps = { events: new EventRegistrationService(store), nowMs: () => NOW, reservationMinutes: 15 };
    return { store, deps };
  }
  const body = { eventId: "ev1", participant: { name: "Ali Veli", email: "ALI@example.com" } };

  it("oturumsuz kayıt reddedilir", async () => {
    const { deps } = setup();
    expect(await failure(reserveEventSpotHandler(deps, null, body))).toBe("unauthenticated:login_required");
  });

  it("geçersiz e-posta alan bazlı reason ile reddedilir", async () => {
    const { deps } = setup();
    const bad = { ...body, participant: { name: "Ali", email: "yanlis" } };
    expect(await failure(reserveEventSpotHandler(deps, authAs("u1"), bad))).toBe(
      "invalid-argument:invalid_email",
    );
  });

  it("başarılı kayıt; kullanıcı kimliği oturumdan gelir, fazladan alanlar kaydedilmez", async () => {
    const { store, deps } = setup();
    const sneaky = {
      ...body,
      userId: "baska-kullanici",
      participant: { ...body.participant, role: "system_admin", isAdmin: true },
    };
    const out = await reserveEventSpotHandler(deps, authAs("u1"), sneaky);
    expect(out.status).toBe("reserved");
    expect(out.reservedUntilMs).toBe(NOW + 15 * 60_000);
    const stored = store.allRegistrations("ev1")[0];
    expect(stored?.userId).toBe("u1");
    expect(Object.keys(stored?.participant ?? {}).sort()).toEqual(["email", "name"]);
    expect(stored?.participant.email).toBe("ali@example.com");
  });

  it("kontenjan dolunca iş kuralı hatası reason ile gelir", async () => {
    const store = new MemoryStore([eventDoc({ capacity: 1, waitlistEnabled: false })]);
    const deps = { events: new EventRegistrationService(store), nowMs: () => NOW, reservationMinutes: 15 };
    await reserveEventSpotHandler(deps, authAs("u1"), body);
    expect(await failure(reserveEventSpotHandler(deps, authAs("u2"), body))).toBe(
      "failed-precondition:sold_out",
    );
  });

  it("iptal: başkası yapamaz, içerik yöneticisi yapabilir", async () => {
    const { deps } = setup();
    const r = await reserveEventSpotHandler(deps, authAs("u1"), body);
    const req = { registrationId: r.registrationId };
    expect(await failure(cancelRegistrationHandler(deps, authAs("intruder"), req))).toBe(
      "permission-denied:",
    );
    expect(await failure(cancelRegistrationHandler(deps, authAs("finans", "finance_manager"), req))).toBe(
      "permission-denied:",
    );
    const out = await cancelRegistrationHandler(deps, authAs("icerik", "content_manager"), req);
    expect(out.refundRequired).toBe(false);
  });
});

describe("bağış işleyicisi", () => {
  function setup(campaign: CampaignInfo | null = { status: "active", currency: "TRY" }) {
    const pending: PendingDonation[] = [];
    const payments = new MemoryPayments();
    let n = 0;
    const deps = {
      payments,
      provider: new SimulatedProvider(),
      campaigns: { get: async () => campaign },
      donations: { createPending: async (d: PendingDonation) => void pending.push(d) },
      nowMs: () => NOW,
      mode: "simulation" as const,
      newId: () => `id${++n}`,
    };
    return { payments, pending, deps };
  }
  const body = {
    campaignId: "c1",
    amountMinor: 25_000,
    clientKey: "client-key-1",
    donor: { name: "Ayşe", email: "ayse@example.com" },
  };

  it("misafir bağışı çalışır; ödeme simülasyon olarak işaretlenir, bağış pending açılır", async () => {
    const { payments, pending, deps } = setup();
    const out = await startDonationHandler(deps, null, body);
    expect(out.status).toBe("pending");
    expect(out.simulated).toBe(true);
    expect(payments.all()[0]?.userId).toBe(null);
    expect(pending.length).toBe(1);
    expect(pending[0]?.paymentId).toBe(out.paymentId);
    expect(pending[0]?.donor).toEqual({ name: "Ayşe", email: "ayse@example.com", anonymous: false });
  });

  it("oturumlu bağış kullanıcıya bağlanır; istemcinin userId'si yok sayılır", async () => {
    const { payments, deps } = setup();
    await startDonationHandler(deps, authAs("u1"), { ...body, userId: "baska" });
    expect(payments.all()[0]?.userId).toBe("u1");
  });

  it("aynı clientKey ile tekrar çağrı yeni ödeme/bağış açmaz", async () => {
    const { payments, pending, deps } = setup();
    await startDonationHandler(deps, null, body);
    const again = await startDonationHandler(deps, null, body);
    expect(again.reused).toBe(true);
    expect(payments.all().length).toBe(1);
    expect(pending.length).toBe(1);
  });

  it("taslak/bulunmayan kampanya ve geçersiz tutar reddedilir", async () => {
    expect(await failure(startDonationHandler(setup({ status: "draft", currency: "TRY" }).deps, null, body))).toBe(
      "failed-precondition:campaign_not_active",
    );
    expect(await failure(startDonationHandler(setup(null).deps, null, body))).toBe("not-found:campaign_not_found");
    for (const amountMinor of ["250", 250.5, 50, -100, 0]) {
      const code = await failure(startDonationHandler(setup().deps, null, { ...body, amountMinor }));
      expect(code.startsWith("invalid-argument:")).toBe(true);
    }
  });

  it("kampanyasız (genel) bağış çalışır", async () => {
    const { payments, deps } = setup(null);
    const { campaignId: _omit, ...general } = body;
    void _omit;
    await startDonationHandler(deps, null, general);
    expect(payments.all()[0]?.refId).toBe("general");
  });

  it("oturum nesnesi bozuksa (uid yok) misafire düşmez, reddedilir", async () => {
    const { deps } = setup();
    expect(await failure(startDonationHandler(deps, { uid: "", token: {} }, body))).toBe(
      "unauthenticated:login_required",
    );
  });
});

describe("manuel ödeme işleyicisi", () => {
  function setup() {
    const audit: AuditEntry[] = [];
    const payments = new MemoryPayments();
    const deps = { payments, audit: { write: async (e: AuditEntry) => void audit.push(e) }, nowMs: () => NOW };
    return { audit, payments, deps };
  }
  const body = {
    kind: "membership_due",
    refId: "due1",
    userId: "u1",
    amountMinor: 120_000,
    receivedAtMs: NOW - DAY,
    note: "Elden teslim alındı",
  };

  it("yetkisiz roller girdi doğrulamasından ÖNCE reddedilir (çöp veri bile ipucu vermez)", async () => {
    const { deps, payments } = setup();
    for (const role of ["content_manager", "system_admin", "club_member", undefined]) {
      expect(await failure(recordManualPaymentHandler(deps, authAs("x", role), { çöp: true }))).toBe(
        "permission-denied:",
      );
    }
    expect(await failure(recordManualPaymentHandler(deps, null, body))).toBe("unauthenticated:login_required");
    expect(payments.all().length).toBe(0);
  });

  it("finans yöneticisi kaydeder; ödeme manuel/gerçek işaretlenir ve denetim yazılır", async () => {
    const { deps, payments, audit } = setup();
    const out = await recordManualPaymentHandler(deps, authAs("fin1", "finance_manager"), body);
    const p = payments.all()[0];
    expect(p?.id).toBe(out.paymentId);
    expect(p?.manual).toBe(true);
    expect(p?.simulated).toBe(false);
    expect(p?.recordedBy).toBe("fin1");
    expect(p?.note).toBe("Elden teslim alındı");
    expect(p?.userId).toBe("u1");
    expect(p?.status).toBe("succeeded");
    expect(p?.succeededAtMs).toBe(NOW - DAY);
    expect(audit.length).toBe(1);
    expect(audit[0]?.action).toBe("payment.manual_record");
    expect(audit[0]?.targetId).toBe(out.paymentId);
    expect(audit[0]?.actorId).toBe("fin1");
  });

  it("aynı ödeme ikinci kez girilemez ve ikinci denetim kaydı yazılmaz", async () => {
    const { deps, audit } = setup();
    const fin = authAs("fin1", "finance_manager");
    await recordManualPaymentHandler(deps, fin, body);
    expect(await failure(recordManualPaymentHandler(deps, fin, body))).toBe(
      "already-exists:duplicate_manual_payment",
    );
    expect(audit.length).toBe(1);
  });

  it("geçersiz girdi alan bazlı reddedilir", async () => {
    const { deps } = setup();
    const fin = authAs("fin1", "finance_manager");
    expect(await failure(recordManualPaymentHandler(deps, fin, { ...body, kind: "hediye" }))).toBe(
      "invalid-argument:invalid_kind",
    );
    expect(await failure(recordManualPaymentHandler(deps, fin, { ...body, note: "kısa" }))).toBe(
      "invalid-argument:invalid_note",
    );
    expect(await failure(recordManualPaymentHandler(deps, fin, { ...body, amountMinor: 10.5 }))).toBe(
      "invalid-argument:invalid_amountMinor",
    );
    expect(await failure(recordManualPaymentHandler(deps, fin, { ...body, receivedAtMs: NOW + DAY }))).toBe(
      "invalid-argument:future_date",
    );
  });
});
