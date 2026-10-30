import { EventDoc, RegistrationDoc } from "../events/capacity";
import { Tx, TxRunner } from "../events/store";
import { PaymentDoc, PaymentTx, PaymentTxRunner } from "../payments/repo";
import { Clock, FsDb, FsDocRef, FsSnap, FsTx } from "./fsTypes";

/**
 * Alan adı eşlemesi: domain `fooMs` (epoch ms) ↔ Firestore `foo` (Timestamp).
 * Örnek: createdAtMs ↔ createdAt, reservedUntilMs ↔ reservedUntil. Adlar DATA_MODEL.md ile aynı.
 */
function toStoreKey(key: string): string {
  return key.endsWith("Ms") ? key.slice(0, -2) : key;
}

export function encode(obj: Record<string, unknown>, clock: Clock): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(obj)) {
    if (v === undefined) continue; // Firestore undefined kabul etmez
    out[toStoreKey(k)] = k.endsWith("Ms") && typeof v === "number" ? clock.fromMs(v) : v;
  }
  return out;
}

function decode(data: Record<string, unknown>, clock: Clock, msKeys: readonly string[]): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(data)) out[k] = v;
  for (const ms of msKeys) {
    const at = toStoreKey(ms);
    const v = data[at];
    delete out[at];
    out[ms] = v === null || v === undefined ? null : clock.toMs(v);
  }
  return out;
}

/** Etkinlikte `registrationDeadline` zorunlu olduğundan null olmaz. */
const EVENT_MS = ["registrationDeadlineMs"] as const;
const REG_MS = ["reservedUntilMs", "createdAtMs", "confirmedAtMs"] as const;
const PAY_MS = ["createdAtMs", "updatedAtMs", "succeededAtMs"] as const;

const EVENT_FIELDS = [
  "capacity", "reservedCount", "confirmedCount", "waitlistEnabled",
  "status", "feeMinor", "currency",
] as const;

function requireSnap(s: FsSnap, what: string): Record<string, unknown> {
  const d = s.data();
  if (!s.exists || !d) throw new Error(`${what} bulunamadı: ${s.id}`);
  return d;
}

function eventFrom(s: FsSnap, clock: Clock): EventDoc {
  const d = decode(requireSnap(s, "etkinlik"), clock, EVENT_MS);
  const e: Record<string, unknown> = { id: s.id, registrationDeadlineMs: d.registrationDeadlineMs };
  for (const f of EVENT_FIELDS) e[f] = d[f];
  return e as unknown as EventDoc;
}

function regFrom(s: FsSnap, clock: Clock): RegistrationDoc {
  const d = decode(requireSnap(s, "kayıt"), clock, REG_MS);
  return {
    id: s.id,
    eventId: d.eventId,
    userId: d.userId,
    participant: d.participant,
    status: d.status,
    paymentId: (d.paymentId as string | null | undefined) ?? null,
    reservedUntilMs: d.reservedUntilMs,
    waitlistPosition: (d.waitlistPosition as number | null | undefined) ?? null,
    createdAtMs: d.createdAtMs,
    confirmedAtMs: d.confirmedAtMs,
  } as unknown as RegistrationDoc;
}

export function payFrom(s: FsSnap, clock: Clock): PaymentDoc {
  const d = decode(requireSnap(s, "ödeme"), clock, PAY_MS);
  return {
    id: s.id,
    kind: d.kind, refId: d.refId,
    userId: (d.userId as string | null | undefined) ?? null,
    amountMinor: d.amountMinor, currency: d.currency, status: d.status,
    provider: d.provider,
    providerRef: (d.providerRef as string | null | undefined) ?? null,
    simulated: d.simulated, idempotencyKey: d.idempotencyKey, manual: d.manual,
    recordedBy: (d.recordedBy as string | null | undefined) ?? null,
    note: (d.note as string | null | undefined) ?? null,
    refundedMinor: d.refundedMinor,
    createdAtMs: d.createdAtMs, updatedAtMs: d.updatedAtMs, succeededAtMs: d.succeededAtMs,
    failureCode: (d.failureCode as string | null | undefined) ?? null,
    flag: (d.flag as string | null | undefined) ?? null,
  } as unknown as PaymentDoc;
}

/**
 * Etkinlik/kayıt transaction'ı. Firestore kuralı: transaction'daki tüm okumalar yazmalardan
 * ÖNCE yapılmalı; servis katmanı buna uyar (test depoları ihlali hata olarak yakalar).
 */
export class FirestoreEventTxRunner implements TxRunner {
  constructor(private readonly db: FsDb, private readonly clock: Clock) {}

  run<T>(fn: (tx: Tx) => Promise<T>): Promise<T> {
    const { db, clock } = this;
    return db.runTransaction(async (fs: FsTx) => {
      const events = db.collection("events");
      const regs = db.collection("event_registrations");
      const tx: Tx = {
        async getEvent(id) {
          const s = await fs.getDoc(events.doc(id));
          return s.exists ? eventFrom(s, clock) : null;
        },
        async putEvent(e) {
          // Yalnızca sayaç alanları güncellenir; içerik alanlarına dokunulmaz.
          fs.update(events.doc(e.id), { reservedCount: e.reservedCount, confirmedCount: e.confirmedCount });
        },
        async getRegistration(id) {
          const s = await fs.getDoc(regs.doc(id));
          return s.exists ? regFrom(s, clock) : null;
        },
        async listRegistrations(eventId) {
          const snaps = await fs.getQuery(regs.where("eventId", "==", eventId));
          return snaps.map((s) => regFrom(s, clock));
        },
        async createRegistration(r) {
          const ref: FsDocRef = regs.doc();
          fs.set(ref, encode(r as unknown as Record<string, unknown>, clock));
          return { ...r, id: ref.id };
        },
        async updateRegistration(id, patch) {
          fs.update(regs.doc(id), encode(patch as Record<string, unknown>, clock));
        },
      };
      return fn(tx);
    });
  }
}

/** Ödeme erişimini mevcut bir transaction üzerinde kurar (iade gibi başka işlemler de kullanır). */
export function buildPaymentTx(db: FsDb, clock: Clock, fs: FsTx): PaymentTx {
  const col = db.collection("payments");
  const first = async (q: ReturnType<typeof col.where>): Promise<PaymentDoc | null> => {
    const snaps = await fs.getQuery(q.limit(1));
    const s = snaps[0];
    return s ? payFrom(s, clock) : null;
  };
  return {
    async getPayment(id) {
      const s = await fs.getDoc(col.doc(id));
      return s.exists ? payFrom(s, clock) : null;
    },
    findByIdempotencyKey: (key) => first(col.where("idempotencyKey", "==", key)),
    findByProviderRef: (ref) => first(col.where("providerRef", "==", ref)),
    async listPendingCreatedBefore(beforeMs, limit) {
      const q = col.where("status", "==", "pending").where("createdAt", "<", clock.fromMs(beforeMs)).limit(limit);
      const snaps = await fs.getQuery(q);
      return snaps.map((s) => payFrom(s, clock));
    },
    async createPayment(d) {
      const ref = col.doc();
      fs.set(ref, encode(d as unknown as Record<string, unknown>, clock));
      return { ...d, id: ref.id };
    },
    async updatePayment(id, patch) {
      fs.update(col.doc(id), encode(patch as Record<string, unknown>, clock));
    },
  };
}

export class FirestorePaymentTxRunner implements PaymentTxRunner {
  constructor(private readonly db: FsDb, private readonly clock: Clock) {}

  run<T>(fn: (tx: PaymentTx) => Promise<T>): Promise<T> {
    const { db, clock } = this;
    return db.runTransaction((fs: FsTx) => fn(buildPaymentTx(db, clock, fs)));
  }
}
