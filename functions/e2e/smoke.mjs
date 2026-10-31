// Emülatörde uçtan uca duman testi: gerçek callable'lar, gerçek Firestore/Auth emülatörü.
// Çalıştırma (repo kökünden): firebase emulators:exec --only functions,firestore,auth --project demo-rotary "node functions/e2e/smoke.mjs"
import assert from "node:assert/strict";
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

const PROJECT = "demo-rotary";
const REGION = "europe-west1";
initializeApp({ projectId: PROJECT });
const db = getFirestore();
const auth = getAuth();
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST ?? "127.0.0.1:9099";
const FN = `http://127.0.0.1:5001/${PROJECT}/${REGION}`;

async function tokenFor(uid, claims) {
  await auth.createUser({ uid, email: `${uid}@example.com`, displayName: uid });
  if (claims) await auth.setCustomUserClaims(uid, claims);
  const custom = await auth.createCustomToken(uid);
  const r = await fetch(`http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=fake`, {
    method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ token: custom, returnSecureToken: true }),
  });
  return (await r.json()).idToken;
}

async function call(name, data, token) {
  const res = await fetch(`${FN}/${name}`, {
    method: "POST",
    headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify({ data }),
  });
  const body = await res.json();
  return body.error ? { error: body.error } : { ok: body.result };
}

const step = async (name, fn) => { await fn(); console.log("  ok  ", name); };

const FUTURE = Timestamp.fromMillis(Date.now() + 7 * 86_400_000);
await db.collection("events").doc("ev1").set({
  title: "Gala", description: "x", location: "Salon", startsAt: FUTURE, registrationDeadline: FUTURE,
  capacity: 1, reservedCount: 0, confirmedCount: 0, waitlistEnabled: true, status: "published", feeMinor: 5000, currency: "TRY",
});
await db.collection("donation_campaigns").doc("c1").set({
  title: "Okul", description: "x", goalMinor: 100000, currency: "TRY", verifiedTotalMinor: 0, donorCount: 0, status: "active",
});

const a = await tokenFor("userA");
const b = await tokenFor("userB");
const admin = await tokenFor("adminU", { role: "system_admin" });
const person = (n) => ({ name: n, email: `${n}@example.com` });
let regA, payA;

await step("giriş yapmadan rezervasyon reddedilir", async () => {
  const r = await call("reserveEventSpot", { eventId: "ev1", participant: person("x") });
  assert.equal(r.error?.status, "UNAUTHENTICATED");
});

await step("A kontenjanı alır (reserved), B bekleme listesine düşer", async () => {
  const ra = await call("reserveEventSpot", { eventId: "ev1", participant: person("userA") }, a);
  assert.equal(ra.ok?.status, "reserved", JSON.stringify(ra));
  regA = ra.ok.registrationId;
  const rb = await call("reserveEventSpot", { eventId: "ev1", participant: person("userB") }, b);
  assert.equal(rb.ok?.status, "waitlisted", JSON.stringify(rb));
  const ev = (await db.collection("events").doc("ev1").get()).data();
  assert.equal(ev.reservedCount, 1);
});

await step("B, A'nın kaydı için ödeme başlatamaz", async () => {
  const r = await call("startEventFeePayment", { registrationId: regA, clientKey: "clientkey_b1" }, b);
  assert.equal(r.error?.status, "NOT_FOUND");
});

await step("A ücret ödemesi başlatır; aynı anahtar aynı ödemeyi verir; tutar sunucudan gelir", async () => {
  const p1 = await call("startEventFeePayment", { registrationId: regA, clientKey: "clientkey_a1", amountMinor: 1 }, a);
  assert.equal(p1.ok?.status, "pending", JSON.stringify(p1));
  const p2 = await call("startEventFeePayment", { registrationId: regA, clientKey: "clientkey_a1" }, a);
  assert.equal(p2.ok.paymentId, p1.ok.paymentId);
  payA = p1.ok.paymentId;
  const doc = (await db.collection("payments").doc(payA).get()).data();
  assert.equal(doc.amountMinor, 5000);
  assert.equal(doc.simulated, true);
});

await step("sistem yöneticisi olmayan simülasyon sonucu veremez", async () => {
  const r = await call("simulatePaymentResult", { paymentId: payA, outcome: "succeeded" }, a);
  assert.equal(r.error?.status, "PERMISSION_DENIED");
});

await step("başarılı ödeme kaydı kesinleştirir ve bildirim üretir; tekrar çağrı çift işlem yapmaz", async () => {
  const r = await call("simulatePaymentResult", { paymentId: payA, outcome: "succeeded" }, admin);
  assert.equal(r.ok?.result, "applied", JSON.stringify(r));
  assert.equal(r.ok.effectsFailed, false);
  assert.equal((await db.collection("event_registrations").doc(regA).get()).data().status, "confirmed");
  const ev = (await db.collection("events").doc("ev1").get()).data();
  assert.equal(ev.confirmedCount, 1);
  assert.equal(ev.reservedCount, 0);
  const notes = await db.collection("notifications").where("userId", "==", "userA").get();
  assert.equal(notes.size, 1);
  assert.equal(notes.docs[0].data().type, "registration_confirmed");
  const again = await call("simulatePaymentResult", { paymentId: payA, outcome: "succeeded" }, admin);
  assert.equal(again.ok?.result, "ignored");
  assert.equal((await db.collection("notifications").where("userId", "==", "userA").get()).size, 1);
});

await step("misafir bağışı başlar; simülasyon bağışı kampanya toplamına GİRMEZ", async () => {
  const bad = await call("startDonation", { campaignId: "c1", amountMinor: 1, donor: { name: "M", email: "m@example.com", anonymous: false }, clientKey: "donkey_001" });
  assert.equal(bad.error?.status, "INVALID_ARGUMENT");
  const d = await call("startDonation", { campaignId: "c1", amountMinor: 5000, donor: { name: "M", email: "m@example.com", anonymous: false }, clientKey: "donkey_002" });
  assert.equal(d.ok?.status, "pending", JSON.stringify(d));
  assert.equal(d.ok.simulated, true);
  const don = (await db.collection("donations").doc(`don_${d.ok.paymentId}`).get()).data();
  assert.equal(don.status, "pending");
  const s = await call("simulatePaymentResult", { paymentId: d.ok.paymentId, outcome: "succeeded" }, admin);
  assert.equal(s.ok?.result, "applied", JSON.stringify(s));
  assert.equal((await db.collection("donations").doc(`don_${d.ok.paymentId}`).get()).data().status, "succeeded");
  assert.equal((await db.collection("donation_campaigns").doc("c1").get()).data().verifiedTotalMinor, 0);
});

await step("KVKK: engel yoksa silme talebi açılır, tekrar çağrı çift talep açmaz", async () => {
  const c = await tokenFor("userC");
  const r1 = await call("requestAccountDeletion", {}, c);
  assert.deepEqual(r1.ok, { accepted: true, blockers: [], alreadyRequested: false });
  const r2 = await call("requestAccountDeletion", {}, c);
  assert.equal(r2.ok?.alreadyRequested, true);
  const blocked = await call("requestAccountDeletion", {}, a); // A'nın gelecekteki onaylı etkinlik kaydı var
  assert.equal(blocked.ok?.accepted, false);
  assert.deepEqual(blocked.ok.blockers, ["future_event_registrations"]);
});

console.log("TÜM ADIMLAR GEÇTİ");
process.exit(0);
