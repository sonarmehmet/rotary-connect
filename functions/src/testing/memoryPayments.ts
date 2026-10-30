import { PaymentDoc, PaymentTx, PaymentTxRunner } from "../payments/repo";

/** Test için bellek içi iyimser transaction deposu (Firestore davranışını taklit eder). */
export class MemoryPayments implements PaymentTxRunner {
  private docs = new Map<string, PaymentDoc>();
  private version = 0;
  private seq = 0;
  retries = 0;

  all(): PaymentDoc[] {
    return [...this.docs.values()];
  }

  async run<T>(fn: (tx: PaymentTx) => Promise<T>): Promise<T> {
    for (let attempt = 0; attempt < 200; attempt++) {
      const start = this.version;
      const draft = new Map(this.docs);
      let seq = this.seq;
      let wrote = false;
      const read = (): void => {
        if (wrote) throw new Error("Firestore kuralı ihlali: transaction içinde yazmadan SONRA okuma yapılamaz");
      };
      const tx: PaymentTx = {
        getPayment: async (id) => {
          read();
          await Promise.resolve();
          return draft.get(id) ?? null;
        },
        findByIdempotencyKey: async (k) => {
          read();
          await Promise.resolve();
          return [...draft.values()].find((d) => d.idempotencyKey === k) ?? null;
        },
        findByProviderRef: async (r) => {
          read();
          await Promise.resolve();
          return [...draft.values()].find((d) => d.providerRef === r) ?? null;
        },
        listPendingCreatedBefore: async (before, limit) => {
          read();
          await Promise.resolve();
          return [...draft.values()]
            .filter((d) => d.status === "pending" && d.createdAtMs < before)
            .slice(0, limit);
        },
        createPayment: async (d) => {
          wrote = true;
          await Promise.resolve();
          seq += 1;
          const doc: PaymentDoc = { ...d, id: `pay_${seq}` };
          draft.set(doc.id, doc);
          return doc;
        },
        updatePayment: async (id, patch) => {
          wrote = true;
          await Promise.resolve();
          const cur = draft.get(id);
          if (!cur) throw new Error(`ödeme yok: ${id}`);
          draft.set(id, { ...cur, ...patch });
        },
      };
      const out = await fn(tx);
      if (this.version !== start) {
        this.retries++;
        continue;
      }
      this.docs = draft;
      this.seq = seq;
      this.version++;
      return out;
    }
    throw new Error("transaction çok fazla çakıştı");
  }
}
