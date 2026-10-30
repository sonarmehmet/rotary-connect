// Firestore güvenlik kuralları testleri (emülatör). DOĞRULANMAMIŞ: henüz çalıştırılmadı.
// Çalıştırma (repo kökünden): cd tests/rules && npm install && npm test
import { readFileSync } from "node:fs";
import { after, before, beforeEach, describe, it } from "node:test";
import { assertFails, assertSucceeds, initializeTestEnvironment } from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc, updateDoc, deleteDoc } from "firebase/firestore";

let env;
const as = (uid, role) => env.authenticatedContext(uid, role ? { role } : {}).firestore();

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-rotary",
    firestore: { rules: readFileSync("../../firebase/firestore.rules", "utf8"), host: "127.0.0.1", port: 8080 },
  });
});
after(() => env.cleanup());
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users/u1"), { email: "a@b.co", name: "Ali" });
    await setDoc(doc(db, "membership_dues/d1"), { userId: "u1", amountMinor: 100, paidMinor: 0 });
    await setDoc(doc(db, "payments/p1"), { userId: "u1", amountMinor: 100, status: "succeeded" });
    await setDoc(doc(db, "audit_logs/a1"), { action: "x" });
    await setDoc(doc(db, "effect_markers/collected:p1"), { createdAt: new Date() });
  });
});

describe("kullanıcı profili", () => {
  it("sahibi okur, başkası okuyamaz", async () => {
    await assertSucceeds(getDoc(doc(as("u1"), "users/u1")));
    await assertFails(getDoc(doc(as("u2"), "users/u1")));
  });
  it("kullanıcı kendine rol yazamaz ve hesabını silemez", async () => {
    await assertFails(updateDoc(doc(as("u1"), "users/u1"), { role: "system_admin" }));
    await assertFails(deleteDoc(doc(as("u1"), "users/u1")));
  });
});

describe("finansal koleksiyonlar", () => {
  it("üye yalnızca kendi borcunu okur; kimse istemciden yazamaz", async () => {
    await assertSucceeds(getDoc(doc(as("u1", "club_member"), "membership_dues/d1")));
    await assertFails(getDoc(doc(as("u2", "club_member"), "membership_dues/d1")));
    await assertFails(updateDoc(doc(as("u1", "club_member"), "membership_dues/d1"), { paidMinor: 100 }));
    await assertFails(updateDoc(doc(as("fin", "finance_manager"), "payments/p1"), { status: "refunded" }));
    await assertFails(setDoc(doc(as("u1"), "payments/p2"), { userId: "u1", amountMinor: 1, status: "succeeded" }));
  });
});

describe("denetim ve sunucu koleksiyonları", () => {
  it("denetim kaydını yalnızca sistem yöneticisi okur, kimse yazmaz", async () => {
    await assertSucceeds(getDoc(doc(as("s", "system_admin"), "audit_logs/a1")));
    await assertFails(getDoc(doc(as("f", "finance_manager"), "audit_logs/a1")));
    await assertFails(setDoc(doc(as("s", "system_admin"), "audit_logs/a2"), { action: "y" }));
  });
  it("effect_markers istemciye tamamen kapalı", async () => {
    await assertFails(getDoc(doc(as("s", "system_admin"), "effect_markers/collected:p1")));
    await assertFails(setDoc(doc(as("u1"), "effect_markers/x"), { a: 1 }));
  });
  it("ziyaretçi korumalı veriyi okuyamaz", async () => {
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), "payments/p1")));
  });
});
