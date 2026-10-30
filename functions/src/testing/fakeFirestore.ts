import { Clock, FsCollection, FsDb, FsDocRef, FsQuery, FsSnap, FsTx } from "../adapters/fsTypes";

type Row = Record<string, unknown>;
interface Filter { field: string; op: "==" | "<" | ">" | "<=" | ">="; value: unknown }

/** Zaman damgasını ham belgede görünür kılan sahte Timestamp. */
export interface FakeTs { readonly __ts: number }
export const fakeClock: Clock = {
  fromMs: (ms) => ({ __ts: ms }) satisfies FakeTs,
  toMs: (v) => (v as FakeTs).__ts,
};

class Ref implements FsDocRef {
  constructor(readonly col: string, readonly id: string) {}
}

function cmp(a: unknown, b: unknown): number {
  const av = (a as FakeTs)?.__ts ?? a;
  const bv = (b as FakeTs)?.__ts ?? b;
  return (av as number) < (bv as number) ? -1 : (av as number) > (bv as number) ? 1 : 0;
}

class Query implements FsQuery {
  constructor(readonly col: string, readonly filters: Filter[] = [], readonly max: number | null = null) {}
  where(field: string, op: Filter["op"], value: unknown): FsQuery {
    return new Query(this.col, [...this.filters, { field, op, value }], this.max);
  }
  limit(n: number): FsQuery {
    return new Query(this.col, this.filters, n);
  }
}

class Collection extends Query implements FsCollection {
  constructor(col: string, private readonly nextId: () => string) {
    super(col);
  }
  doc(id?: string): FsDocRef {
    return new Ref(this.col, id ?? this.nextId());
  }
}

/**
 * Sahte Firestore: transaction'lar sıraya dizilir, yazmalar commit'e kadar tamponlanır ve
 * "yazmadan sonra okuma" gerçek Firestore gibi hata verir. Ham belgeler `raw()` ile incelenebilir.
 */
export class FakeFirestore implements FsDb {
  private data = new Map<string, Map<string, Row>>();
  private seq = 0;
  private chain: Promise<unknown> = Promise.resolve();

  private table(name: string): Map<string, Row> {
    let t = this.data.get(name);
    if (!t) this.data.set(name, (t = new Map()));
    return t;
  }

  seed(col: string, id: string, row: Row): void {
    this.table(col).set(id, row);
  }

  raw(col: string): { id: string; data: Row }[] {
    return [...this.table(col).entries()].map(([id, data]) => ({ id, data }));
  }

  collection(name: string): FsCollection {
    return new Collection(name, () => `auto_${++this.seq}`);
  }

  runTransaction<T>(fn: (tx: FsTx) => Promise<T>): Promise<T> {
    const run = async (): Promise<T> => {
      const writes: (() => void)[] = [];
      let wrote = false;
      const guard = (): void => {
        if (wrote) throw new Error("Firestore kuralı ihlali: transaction içinde yazmadan SONRA okuma yapılamaz");
      };
      const snapOf = (col: string, id: string): FsSnap => {
        const row = this.table(col).get(id);
        return { id, exists: row !== undefined, data: () => (row ? { ...row } : undefined) };
      };
      const tx: FsTx = {
        getDoc: async (ref) => {
          guard();
          const r = ref as Ref;
          return snapOf(r.col, r.id);
        },
        getQuery: async (q) => {
          guard();
          const query = q as Query;
          let rows = [...this.table(query.col).entries()].filter(([, row]) =>
            query.filters.every((f) => {
              const c = cmp(row[f.field], f.value);
              return f.op === "==" ? c === 0 && row[f.field] !== undefined
                : f.op === "<" ? c < 0 : f.op === ">" ? c > 0 : f.op === "<=" ? c <= 0 : c >= 0;
            }),
          );
          if (query.max !== null) rows = rows.slice(0, query.max);
          return rows.map(([id]) => snapOf(query.col, id));
        },
        set: (ref, d) => {
          wrote = true;
          const r = ref as Ref;
          writes.push(() => this.table(r.col).set(r.id, { ...d }));
        },
        update: (ref, d) => {
          wrote = true;
          const r = ref as Ref;
          writes.push(() => {
            const cur = this.table(r.col).get(r.id);
            if (!cur) throw new Error(`update: belge yok ${r.col}/${r.id}`);
            this.table(r.col).set(r.id, { ...cur, ...d });
          });
        },
      };
      const result = await fn(tx);
      for (const w of writes) w();
      return result;
    };
    const next = this.chain.then(run, run);
    this.chain = next.catch(() => undefined);
    return next;
  }
}
