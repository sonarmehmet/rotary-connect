import { describe, expect, it } from "vitest";
import { AuditEntry } from "../audit/audit";
import { DEFAULT_PREFS, NotificationPrefs } from "../notifications/notifications";
import { toCallableError } from "./callableError";
import {
  Audience,
  NotificationItem,
  Recipient,
  containsSensitive,
  sendAnnouncementHandler,
} from "./announce";
import { CallableAuth } from "./handlers";

const NOW = 1_800_000_000_000;
const authAs = (uid: string, role?: string): CallableAuth => ({ uid, token: role === undefined ? {} : { role } });

async function failure(p: Promise<unknown>): Promise<string> {
  try {
    await p;
    return "no-error";
  } catch (e) {
    const c = toCallableError(e);
    return `${c.code}:${c.reason ?? ""}`;
  }
}

function setup(users: Recipient[], pageSize = 2) {
  const store = new Map<string, NotificationItem>();
  const audit: AuditEntry[] = [];
  const seenAudiences: Audience[] = [];
  let writeCalls = 0;
  const deps = {
    recipients: {
      page: async (a: Audience, cursor: string | null, limit: number) => {
        seenAudiences.push(a);
        const start = cursor === null ? 0 : Number(cursor);
        const slice = users.slice(start, start + limit);
        const end = start + limit;
        return { recipients: slice, next: end < users.length ? String(end) : null };
      },
    },
    notifications: {
      createIfAbsent: async (items: readonly NotificationItem[]) => {
        writeCalls++;
        for (const it of items) if (!store.has(it.id)) store.set(it.id, it);
      },
    },
    audit: { write: async (e: AuditEntry) => void audit.push(e) },
    nowMs: () => NOW,
    pageSize,
  };
  return { store, audit, seenAudiences, deps, calls: () => writeCalls };
}

const users = (n: number, prefs: NotificationPrefs = DEFAULT_PREFS): Recipient[] =>
  Array.from({ length: n }, (_, i) => ({ userId: `u${i + 1}`, prefs }));

const body = {
  audience: { type: "all" },
  title: "Yıllık gala",
  body: "Cumartesi akşamı kulüpte buluşuyoruz.",
  route: "/events",
  clientKey: "ann-key-0001",
};

describe("duyuru içerik denetimi", () => {
  it("tutar, e-posta, telefon/TCKN ve IBAN yakalanır; tarih ve saat serbest", () => {
    for (const bad of ["Gala 500 TL", "1.250,50₺ ödeyin", "ali@example.com", "0532 123 45 67", "12345678901", "TR33 0006"]) {
      expect(containsSensitive(bad)).toBe(true);
    }
    for (const ok of ["Cumartesi 30.10.2026 saat 18:00", "Yeni proje başladı", "2026-2027 dönemi"]) {
      expect(containsSensitive(ok)).toBe(false);
    }
  });
});

describe("sendAnnouncement", () => {
  it("yalnızca içerik ve sistem yöneticisi gönderebilir; yetki girdiden önce denetlenir", async () => {
    const { deps, store } = setup(users(3));
    for (const role of ["finance_manager", "club_member", undefined]) {
      expect(await failure(sendAnnouncementHandler(deps, authAs("x", role), { çöp: 1 }))).toBe("permission-denied:");
    }
    expect(await failure(sendAnnouncementHandler(deps, null, body))).toBe("unauthenticated:login_required");
    expect(store.size).toBe(0);
  });

  it("tüm kullanıcılara sayfalayarak gönderir; bildirim içeriği doğru ve hassas veri yok", async () => {
    const { deps, store, audit } = setup(users(5), 2);
    const out = await sendAnnouncementHandler(deps, authAs("icerik", "content_manager"), body);
    expect(out).toEqual({ recipients: 5, sent: 5, skippedByPreferences: 0 });
    expect(store.size).toBe(5);
    const n = [...store.values()][0]?.doc;
    expect(n?.type).toBe("announcement");
    expect(n?.read).toBe(false);
    expect(n?.data.route).toBe("/events");
    expect(n?.createdAtMs).toBe(NOW);
    expect(audit.length).toBe(1);
    expect(audit[0]?.action).toBe("announcement.send");
    expect(audit[0]?.after).toEqual({ audience: "all", route: "/events", recipients: 5, sent: 5 });
  });

  it("duyuru tercihini kapatanlara gönderilmez ve sayılır", async () => {
    const off = { ...DEFAULT_PREFS, announcements: false };
    const { deps, store } = setup([...users(2), { userId: "kapali", prefs: off }]);
    const out = await sendAnnouncementHandler(deps, authAs("icerik", "content_manager"), body);
    expect(out).toEqual({ recipients: 3, sent: 2, skippedByPreferences: 1 });
    expect([...store.values()].some((i) => i.doc.userId === "kapali")).toBe(false);
  });

  it("TEKRAR deneme çift bildirim üretmez; okunmuş bildirim sıfırlanmaz", async () => {
    const { deps, store } = setup(users(3));
    const admin = authAs("icerik", "content_manager");
    await sendAnnouncementHandler(deps, admin, body);
    const first = [...store.values()][0];
    if (first) store.set(first.id, { ...first, doc: { ...first.doc, read: true } });
    await sendAnnouncementHandler(deps, admin, body);
    expect(store.size).toBe(3);
    expect(store.get(first?.id ?? "")?.doc.read).toBe(true);
  });

  it("farklı clientKey yeni bildirim üretir", async () => {
    const { deps, store } = setup(users(2));
    const admin = authAs("icerik", "content_manager");
    await sendAnnouncementHandler(deps, admin, body);
    await sendAnnouncementHandler(deps, admin, { ...body, clientKey: "ann-key-0002" });
    expect(store.size).toBe(4);
  });

  it("hedef kitle ayrıştırılır: üyeler ve rol; ziyaretçi/bilinmeyen rol reddedilir", async () => {
    const { deps, seenAudiences } = setup(users(1));
    const admin = authAs("a", "system_admin");
    await sendAnnouncementHandler(deps, admin, { ...body, audience: { type: "members" } });
    await sendAnnouncementHandler(deps, admin, { ...body, audience: { type: "role", role: "finance_manager" } });
    expect(seenAudiences[0]).toEqual({ type: "members" });
    expect(seenAudiences[1]).toEqual({ type: "role", role: "finance_manager" });
    for (const audience of [{ type: "role", role: "visitor" }, { type: "role", role: "root" }, { type: "herkes" }, "all"]) {
      expect(await failure(sendAnnouncementHandler(deps, admin, { ...body, audience }))).toBe(
        "invalid-argument:invalid_audience",
      );
    }
  });

  it("rota izin listesi dışındaysa reddedilir (finans ekranı dahil)", async () => {
    const { deps } = setup(users(1));
    const admin = authAs("a", "content_manager");
    for (const route of ["/dues", "https://kotu.example", "//x", "/admin"]) {
      expect(await failure(sendAnnouncementHandler(deps, admin, { ...body, route }))).toBe("invalid-argument:invalid_route");
    }
  });

  it("hassas içerik ve kötü clientKey reddedilir; hiçbir şey yazılmaz", async () => {
    const { deps, store, audit } = setup(users(2));
    const admin = authAs("a", "content_manager");
    expect(await failure(sendAnnouncementHandler(deps, admin, { ...body, body: "Katılım ücreti 500 TL" }))).toBe(
      "invalid-argument:sensitive_content",
    );
    expect(await failure(sendAnnouncementHandler(deps, admin, { ...body, title: "Bize yazın: a@b.com" }))).toBe(
      "invalid-argument:sensitive_content",
    );
    expect(await failure(sendAnnouncementHandler(deps, admin, { ...body, clientKey: "bad key/with space" }))).toBe(
      "invalid-argument:invalid_clientKey",
    );
    expect(await failure(sendAnnouncementHandler(deps, admin, { ...body, title: "x".repeat(81) }))).toBe(
      "invalid-argument:invalid_title",
    );
    expect(store.size).toBe(0);
    expect(audit.length).toBe(0);
  });

  it("büyük kitle 400'lük gruplara bölünür", async () => {
    const { deps, store, calls } = setup(users(1000), 1000);
    await sendAnnouncementHandler(deps, authAs("a", "content_manager"), body);
    expect(store.size).toBe(1000);
    expect(calls()).toBe(3); // 400 + 400 + 200
  });

  it("alıcı yoksa sıfır sonuç döner ve yine denetlenir", async () => {
    const { deps, audit } = setup([]);
    const out = await sendAnnouncementHandler(deps, authAs("a", "content_manager"), body);
    expect(out).toEqual({ recipients: 0, sent: 0, skippedByPreferences: 0 });
    expect(audit.length).toBe(1);
  });
});
