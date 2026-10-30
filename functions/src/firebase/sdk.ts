import { Firestore, Timestamp } from "firebase-admin/firestore";
import { Clock, FsCollection, FsDb, FsDocRef, FsQuery, FsSnap, FsTx } from "../adapters/fsTypes";

/**
 * `firebase-admin` Firestore'unu `FsDb` arayüzüne saran ince katman. DOĞRULANMAMIŞ: bu paketler bu
 * ortamda kurulamadı; ilk `npm install && npm run build` sonrası derleme hataları buradan beklenir.
 */
export const timestampClock: Clock = {
  fromMs: (ms) => Timestamp.fromMillis(ms),
  toMs: (v) => {
    if (v instanceof Timestamp) return v.toMillis();
    throw new Error("Zaman damgası bekleniyordu");
  },
};

type FsQueryImpl = FirebaseFirestore.Query;

class Ref implements FsDocRef {
  constructor(readonly raw: FirebaseFirestore.DocumentReference) {}
  get id(): string {
    return this.raw.id;
  }
}

class Query implements FsQuery {
  constructor(readonly raw: FsQueryImpl) {}
  where(field: string, op: "==" | "<" | ">" | "<=" | ">=", value: unknown): FsQuery {
    return new Query(this.raw.where(field, op, value));
  }
  limit(n: number): FsQuery {
    return new Query(this.raw.limit(n));
  }
}

class Collection extends Query implements FsCollection {
  constructor(private readonly col: FirebaseFirestore.CollectionReference) {
    super(col);
  }
  doc(id?: string): FsDocRef {
    return new Ref(id === undefined ? this.col.doc() : this.col.doc(id));
  }
}

const snap = (s: FirebaseFirestore.DocumentSnapshot): FsSnap => ({
  id: s.id,
  exists: s.exists,
  data: () => s.data() as Record<string, unknown> | undefined,
});

export function fsDb(db: Firestore): FsDb {
  return {
    collection: (name) => new Collection(db.collection(name)),
    runTransaction: <T>(fn: (tx: FsTx) => Promise<T>): Promise<T> =>
      db.runTransaction(async (t) =>
        fn({
          getDoc: async (ref) => snap(await t.get((ref as Ref).raw)),
          getQuery: async (q) => (await t.get((q as Query).raw)).docs.map(snap),
          set: (ref, data) => void t.set((ref as Ref).raw, data),
          update: (ref, data) => void t.update((ref as Ref).raw, data),
        }),
      ),
  };
}
