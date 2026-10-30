import { Auth, getAuth } from "firebase-admin/auth";
import {
  DocumentReference, Firestore, Query, Timestamp, Transaction, getFirestore,
} from "firebase-admin/firestore";
import { ROLES, Role, parseRole } from "../lib/roles";
import { AuthRolePort } from "./adminFirestore";
import { Clock, FsCollection, FsDb, FsDocRef, FsQuery, FsSnap, FsTx } from "./fsTypes";

/**
 * `firebase-admin` ↔ `FsDb` ince sarmalayıcısı. İş mantığı yalnızca `fsTypes.ts` arayüzlerini
 * bilir; bu dosya gerçek SDK'ya dokunan TEK yerdir. DOĞRULANMAMIŞ: emülatörde çalıştırılmadı
 * (yalnızca tip denetiminden geçti).
 */

class Ref implements FsDocRef {
  constructor(readonly raw: DocumentReference) {}
  get id(): string {
    return this.raw.id;
  }
}

class Q implements FsQuery {
  constructor(readonly raw: Query) {}
  where(field: string, op: "==" | "<" | ">" | "<=" | ">=", value: unknown): FsQuery {
    return new Q(this.raw.where(field, op, value));
  }
  limit(n: number): FsQuery {
    return new Q(this.raw.limit(n));
  }
}

class Col extends Q implements FsCollection {
  constructor(private readonly fs: Firestore, private readonly name: string) {
    super(fs.collection(name));
  }
  doc(id?: string): FsDocRef {
    const c = this.fs.collection(this.name);
    return new Ref(id === undefined ? c.doc() : c.doc(id));
  }
}

function snapOf(s: { id: string; exists: boolean; data(): FirebaseFirestore.DocumentData | undefined }): FsSnap {
  return { id: s.id, exists: s.exists, data: () => s.data() };
}

export const timestampClock: Clock = {
  fromMs: (ms) => Timestamp.fromMillis(ms),
  toMs: (v) => {
    if (v instanceof Timestamp) return v.toMillis();
    if (typeof v === "number") return v;
    throw new Error("zaman damgası bekleniyordu");
  },
};

export class AdminSdkFirestore implements FsDb {
  constructor(private readonly fs: Firestore = getFirestore()) {}

  collection(name: string): FsCollection {
    return new Col(this.fs, name);
  }

  runTransaction<T>(fn: (tx: FsTx) => Promise<T>): Promise<T> {
    return this.fs.runTransaction(async (t: Transaction) => {
      const tx: FsTx = {
        getDoc: async (ref) => snapOf(await t.get((ref as Ref).raw)),
        getQuery: async (q) => (await t.get((q as Q).raw)).docs.map(snapOf),
        set: (ref, data) => void t.set((ref as Ref).raw, data),
        update: (ref, data) => void t.update((ref as Ref).raw, data),
      };
      return fn(tx);
    });
  }
}

/** Rol Auth custom claim'indedir (`role`); claim yoksa `registered_user`. */
export class AdminSdkAuthRoles implements AuthRolePort {
  constructor(private readonly auth: Auth = getAuth()) {}

  async getRole(userId: string): Promise<Role | null> {
    try {
      const u = await this.auth.getUser(userId);
      const claim = u.customClaims?.["role"];
      return claim === undefined ? "registered_user" : parseRole(claim);
    } catch (e) {
      if ((e as { code?: string }).code === "auth/user-not-found") return null;
      throw e;
    }
  }

  async setRole(userId: string, role: Role): Promise<void> {
    const u = await this.auth.getUser(userId);
    await this.auth.setCustomUserClaims(userId, { ...(u.customClaims ?? {}), role });
  }

  /** Küçük kulüp ölçeği için tüm kullanıcılar taranır (yalnızca `last_admin` denetimi kullanır). */
  async countWithRole(role: Role): Promise<number> {
    let count = 0;
    let pageToken: string | undefined;
    do {
      const page = await this.auth.listUsers(1000, pageToken);
      for (const u of page.users) {
        const claim = u.customClaims?.["role"];
        const r: Role = claim === undefined || !ROLES.includes(claim as Role) ? "registered_user" : (claim as Role);
        if (r === role) count++;
      }
      pageToken = page.pageToken;
    } while (pageToken);
    return count;
  }
}
