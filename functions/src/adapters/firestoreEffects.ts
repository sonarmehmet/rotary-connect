import { DueStatus } from "../dues/dues";
import { DueEntry, DuePaymentRecord, EffectsTx, EffectsTxRunner } from "../payments/effects";
import { Clock, FsDb, FsSnap, FsTx } from "./fsTypes";

/** Koleksiyon adları (DATA_MODEL.md). `effect_markers` yalnızca sunucuya açıktır (kurallarda varsayılan: kapalı). */
const DUES = "membership_dues";
const DUE_PAYMENTS = "membership_due_payments";
const DONATIONS = "donations";
const CAMPAIGNS = "donation_campaigns";
const MARKERS = "effect_markers";

function dueFrom(s: FsSnap, clock: Clock): DueEntry {
  const d = s.data();
  if (!s.exists || !d) throw new Error(`borç bulunamadı: ${s.id}`);
  const status = d["status"] as DueStatus;
  return {
    id: s.id,
    userId: d["userId"] as string,
    currency: d["currency"] as string,
    amountMinor: d["amountMinor"] as number,
    paidMinor: (d["paidMinor"] as number | undefined) ?? 0,
    dueDateMs: clock.toMs(d["dueDate"]),
    cancelled: status === "cancelled",
    refunded: status === "refunded",
    allowPartial: (d["allowPartial"] as boolean | undefined) ?? false,
  };
}

/**
 * Ödeme etkileri transaction'ı. Firestore kuralı: tüm okumalar yazmalardan ÖNCE. `effects.ts`
 * bu sırayı zaten izler; yazmalar arayüzde eşzamanlıdır (tamponlanır) ve transaction sonunda uygulanır.
 */
export class FirestoreEffectsTxRunner implements EffectsTxRunner {
  constructor(private readonly db: FsDb, private readonly clock: Clock) {}

  run<T>(fn: (tx: EffectsTx) => Promise<T>): Promise<T> {
    const { db, clock } = this;
    return db.runTransaction(async (fs: FsTx) => {
      const tx: EffectsTx = {
        async hasMarker(key) {
          return (await fs.getDoc(db.collection(MARKERS).doc(key))).exists;
        },
        async getDue(id) {
          const s = await fs.getDoc(db.collection(DUES).doc(id));
          return s.exists ? dueFrom(s, clock) : null;
        },
        async getDonationByPayment(paymentId) {
          const snaps = await fs.getQuery(db.collection(DONATIONS).where("paymentId", "==", paymentId).limit(1));
          const s = snaps[0];
          return s ? { id: s.id, status: String(s.data()?.["status"] ?? "") } : null;
        },
        async getCampaign(id) {
          const s = await fs.getDoc(db.collection(CAMPAIGNS).doc(id));
          const d = s.data();
          if (!s.exists || !d) return null;
          return {
            verifiedTotalMinor: (d["verifiedTotalMinor"] as number | undefined) ?? 0,
            donorCount: (d["donorCount"] as number | undefined) ?? 0,
          };
        },
        setMarker(key, nowMs) {
          fs.set(db.collection(MARKERS).doc(key), { createdAt: clock.fromMs(nowMs) });
        },
        updateDue(id, patch) {
          fs.update(db.collection(DUES).doc(id), { paidMinor: patch.paidMinor, status: patch.status });
        },
        createDuePayment(r: DuePaymentRecord) {
          fs.set(db.collection(DUE_PAYMENTS).doc(`${r.paymentId}`), {
            dueId: r.dueId,
            paymentId: r.paymentId,
            userId: r.userId,
            amountMinor: r.amountMinor,
            currency: r.currency,
            source: r.source,
            createdAt: clock.fromMs(r.createdAtMs),
          });
        },
        updateDonation(id, patch) {
          fs.update(db.collection(DONATIONS).doc(id), { status: patch.status });
        },
        updateCampaign(id, patch) {
          fs.update(db.collection(CAMPAIGNS).doc(id), {
            verifiedTotalMinor: patch.verifiedTotalMinor,
            donorCount: patch.donorCount,
          });
        },
      };
      return fn(tx);
    });
  }
}
