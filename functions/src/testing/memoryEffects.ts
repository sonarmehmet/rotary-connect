import { DueStatus } from "../dues/dues";
import { DueEntry, DuePaymentRecord, EffectsTx, EffectsTxRunner } from "../payments/effects";

export interface DonationRow {
  id: string;
  paymentId: string;
  status: string;
}

/**
 * Test için bellek içi depo: transaction'lar sıraya dizilir, yazmalar tamponlanır ve hata olursa
 * atılır, "yazmadan sonra okuma" gerçek Firestore gibi hata verir.
 */
export class MemoryEffects implements EffectsTxRunner {
  dues = new Map<string, DueEntry & { status: DueStatus }>();
  duePayments: DuePaymentRecord[] = [];
  donations = new Map<string, DonationRow>();
  campaigns = new Map<string, { verifiedTotalMinor: number; donorCount: number }>();
  markers = new Set<string>();
  private chain: Promise<unknown> = Promise.resolve();

  run<T>(fn: (tx: EffectsTx) => Promise<T>): Promise<T> {
    const exec = async (): Promise<T> => {
      const writes: (() => void)[] = [];
      let wrote = false;
      const read = (): void => {
        if (wrote) throw new Error("Firestore kuralı ihlali: transaction içinde yazmadan SONRA okuma yapılamaz");
      };
      const queue = (w: () => void): void => {
        wrote = true;
        writes.push(w);
      };
      const tx: EffectsTx = {
        hasMarker: async (k) => (read(), this.markers.has(k)),
        getDue: async (id) => (read(), this.dues.get(id) ?? null),
        getDonationByPayment: async (pid) => (read(), [...this.donations.values()].find((d) => d.paymentId === pid) ?? null),
        getCampaign: async (id) => (read(), this.campaigns.get(id) ?? null),
        setMarker: (k) => queue(() => void this.markers.add(k)),
        updateDue: (id, patch) =>
          queue(() => {
            const cur = this.dues.get(id);
            if (!cur) throw new Error(`borç yok: ${id}`);
            this.dues.set(id, { ...cur, ...patch });
          }),
        createDuePayment: (r) => queue(() => void this.duePayments.push(r)),
        updateDonation: (id, patch) =>
          queue(() => {
            const cur = this.donations.get(id);
            if (!cur) throw new Error(`bağış yok: ${id}`);
            this.donations.set(id, { ...cur, ...patch });
          }),
        updateCampaign: (id, patch) => queue(() => void this.campaigns.set(id, { ...patch })),
      };
      const result = await fn(tx);
      for (const w of writes) w();
      return result;
    };
    const next = this.chain.then(exec, exec);
    this.chain = next.catch(() => undefined);
    return next;
  }
}
