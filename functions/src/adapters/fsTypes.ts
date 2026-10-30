/**
 * Firestore'un ihtiyaç duyduğumuz küçük alt kümesi. `firebase-admin` bu oturumda kurulamadığı için
 * adaptörler SDK'ya değil bu arayüzlere bağlıdır; gerçek SDK ile bağlantı `adapters/sdk.ts`
 * içinde ince bir sarmalayıcıyla yapılacaktır (bkz. docs/PROGRESS.md, DOĞRULANMAMIŞ).
 */
export interface FsDocRef {
  readonly id: string;
}

export interface FsSnap {
  readonly id: string;
  readonly exists: boolean;
  data(): Record<string, unknown> | undefined;
}

export interface FsQuery {
  where(field: string, op: "==" | "<" | ">" | "<=" | ">=", value: unknown): FsQuery;
  limit(n: number): FsQuery;
}

export interface FsCollection extends FsQuery {
  /** `id` verilmezse otomatik kimlik üretir. */
  doc(id?: string): FsDocRef;
}

export interface FsTx {
  getDoc(ref: FsDocRef): Promise<FsSnap>;
  getQuery(q: FsQuery): Promise<readonly FsSnap[]>;
  set(ref: FsDocRef, data: Record<string, unknown>): void;
  update(ref: FsDocRef, data: Record<string, unknown>): void;
}

export interface FsDb {
  collection(name: string): FsCollection;
  runTransaction<T>(fn: (tx: FsTx) => Promise<T>): Promise<T>;
}

/** Zaman damgası dönüşümü: alan adı sonekleri `...At` (Timestamp) ↔ `...Ms` (domain). */
export interface Clock {
  fromMs(ms: number): unknown;
  toMs(value: unknown): number;
}
