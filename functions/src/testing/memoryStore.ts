import { EventDoc, RegistrationDoc } from "../events/capacity";
import { Tx, TxRunner } from "../events/store";

interface State {
  events: Map<string, EventDoc>;
  regs: Map<string, RegistrationDoc>;
  seq: number;
}

class ConflictError extends Error {}

/**
 * Test için bellek içi İYİMSER (optimistic) transaction deposu: Firestore transaction
 * davranışını taklit eder. Transaction başında anlık görüntü alınır; commit anında
 * başka bir transaction araya girmişse ConflictError ile baştan denenir.
 * await noktalarında diğer çağrılar araya girebildiği için eşzamanlılık testleri anlamlıdır.
 */
export class MemoryStore implements TxRunner {
  private state: State = { events: new Map(), regs: new Map(), seq: 0 };
  private version = 0;
  retries = 0;

  constructor(events: EventDoc[] = []) {
    for (const e of events) this.state.events.set(e.id, e);
  }

  snapshotEvent(id: string): EventDoc | undefined {
    return this.state.events.get(id);
  }

  allRegistrations(eventId: string): RegistrationDoc[] {
    return [...this.state.regs.values()].filter((r) => r.eventId === eventId);
  }

  async run<T>(fn: (tx: Tx) => Promise<T>): Promise<T> {
    for (let attempt = 0; attempt < 200; attempt++) {
      const startVersion = this.version;
      const draft: State = {
        events: new Map(this.state.events),
        regs: new Map(this.state.regs),
        seq: this.state.seq,
      };
      let wrote = false;
      const read = (): void => {
        if (wrote) throw new Error("Firestore kuralı ihlali: transaction içinde yazmadan SONRA okuma yapılamaz");
      };
      const tx: Tx = {
        getEvent: async (id) => {
          read();
          await Promise.resolve();
          return draft.events.get(id) ?? null;
        },
        putEvent: async (e) => {
          wrote = true;
          await Promise.resolve();
          draft.events.set(e.id, e);
        },
        getRegistration: async (id) => {
          read();
          await Promise.resolve();
          return draft.regs.get(id) ?? null;
        },
        listRegistrations: async (eventId) => {
          read();
          await Promise.resolve();
          return [...draft.regs.values()].filter((r) => r.eventId === eventId);
        },
        createRegistration: async (r) => {
          wrote = true;
          await Promise.resolve();
          draft.seq += 1;
          const doc: RegistrationDoc = { ...r, id: `reg_${draft.seq}` };
          draft.regs.set(doc.id, doc);
          return doc;
        },
        updateRegistration: async (id, patch) => {
          wrote = true;
          await Promise.resolve();
          const cur = draft.regs.get(id);
          if (!cur) throw new Error(`kayıt yok: ${id}`);
          draft.regs.set(id, { ...cur, ...patch });
        },
      };

      const result = await fn(tx);
      if (this.version !== startVersion) {
        this.retries++;
        continue; // başka bir transaction araya girdi: baştan dene
      }
      this.state = draft;
      this.version++;
      return result;
    }
    throw new ConflictError("transaction çok fazla çakıştı");
  }
}
