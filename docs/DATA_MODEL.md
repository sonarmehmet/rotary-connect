# Veri Modeli (Firestore) — v1

Ortak sözleşme: mobil, admin web ve functions bu şemaya göre çalışır. Değişiklik yalnızca
Hesap A tarafından yapılır; diğerleri `PROGRESS.md`'ye değişiklik isteği yazar. Şema değişirse
bu dosya, `firebase/firestore.rules`, `firebase/firestore.indexes.json` ve `packages/shared` aynı commit'te güncellenir.

## Genel kurallar

- **Alan adı eşlemesi (backend):** domain kodundaki `xxxMs` (epoch ms) Firestore'da `xxx` adlı Timestamp'tır (`createdAtMs` ↔ `createdAt`).
- **Firestore transaction kuralı:** tüm okumalar yazmalardan önce yapılır.
- **Para:** `amountMinor` (int, kuruş) + `currency` (string, "TRY"). Asla double.
- **Zaman:** Firestore `Timestamp` (UTC). Gösterim `Europe/Istanbul`. Alan adları `...At` (an) veya `...Date` (yalnızca tarih, Timestamp gün başlangıcı İstanbul saatiyle).
- **Kimlik:** belge kimliği = Firestore otomatik id, aksi belirtilmedikçe. `users/{uid}` = Auth uid.
- **Rol:** Auth custom claim `role` (belgede tutulmaz). `club_member` claim'i yönetici onayıyla verilir.
- **Silme yok (finansal):** `payments`, `refunds`, `donations`, `membership_*`, `audit_logs` silinmez; durum alanıyla iptal/düzeltme.
- **Yazma yetkisi:** "F" = yalnızca Cloud Functions (Admin SDK). "İ" = içerik yöneticisi (+ sistem yöneticisi) istemciden. "K" = kullanıcı kendi belgesini sınırlı alanlarla.
- Sayaç ve toplam alanları (`verifiedTotalMinor`, `reservedCount`, `confirmedCount`) yalnızca Functions transaction'ıyla değişir.

## Ortak durumlar

`PaymentStatus`: created → pending → succeeded | failed | cancelled; succeeded → refunded | partially_refunded; partially_refunded → refunded.
(Dart: `packages/shared/lib/src/payment_status.dart`, TS: `functions/src/payments/paymentState.ts`; birebir aynı.)

`PaymentKind`: `membership_due` | `donation` | `event_fee`.

## Koleksiyonlar

### users/{uid} — yazma: K (rol ve e-posta hariç), oluşturma: K
`displayName`, `email`, `phone?`, `createdAt`, `notificationPrefs {events, dues, donations, announcements}: bool`, `fcmTokens: string[]`, `deletionRequestedAt?`.
Yaşam döngüsü: kayıt → profil; silme talebi → Functions anonimleştirir (finansal kayıtlar yasal saklama için kimliksiz tutulur).

### club_members/{id} — yazma: F
`userId`, `memberNo`, `status: pending|active|suspended|resigned`, `joinedAt?`, `approvedBy?`, `requestedAt`.
Üyelik talebi kullanıcıdan callable ile gelir (`requestMembership`), yönetici onaylar → claim `club_member` atanır.

### membership_dues/{id} — yazma: F
`userId`, `memberId`, `periodId`, `periodLabel` (ör. "2026-2027"), `amountMinor`, `currency`, `paidMinor`, `dueDate`, `status: unpaid|partially_paid|paid|overdue|cancelled|refunded`, `allowPartial: bool`, `createdBy`, `createdAt`.
`overdue` zamanlanmış function ile hesaplanır. Tutar ve dönemler kodda sabit değil; panelden atanır.

### membership_due_payments/{id} — yazma: F
`dueId`, `paymentId`, `userId`, `amountMinor`, `currency`, `source: online|manual`, `createdAt`. Borç ↔ ödeme bağı (kısmi ödeme çoklu kayıt üretir).

### donation_campaigns/{id} — yazma: İ (`verifiedTotalMinor` hariç)
`title`, `description`, `category: education|health|scholarship|children|disaster|environment|general`, `imagePath?`, `goalMinor`, `currency`, `verifiedTotalMinor` (F), `donorCount` (F), `status: draft|active|completed|archived`, `endsAt?`, `projectId?`, `eventId?`, `createdAt`.
Gösterilen "toplanan" yalnızca `verifiedTotalMinor`. İade olursa Functions düşer.

### donations/{id} — yazma: F
`campaignId?` (null = genel), `paymentId`, `userId?` (misafir olabilir), `donor {name, email?, phone?, anonymous: bool}`, `amountMinor`, `currency`, `status` (payments ile eş), `receiptNo?`, `createdAt`.
Misafir bağışı okunabilirliği: referans + e-posta ile callable `getDonationReceipt`; doğrudan istemci okuması yalnızca `userId` sahibine.

### payments/{id} — yazma: F
`kind`, `refId` (due/donation/registration id), `userId?`, `amountMinor`, `currency`, `status`, `provider` ("simulation"|"iyzico"|"paytr"), `providerRef?`, `simulated: bool`, `idempotencyKey`, `manual: bool`, `recordedBy?` (manuel için), `note?`, `failureCode?`, `flag?` (şüpheli durum, ör. `amount_mismatch`; bayraklı ödeme tahsilat sayılmaz, insan incelemesi gerekir), `refundedMinor` (varsayılan 0), `createdAt`, `updatedAt`, `succeededAt?`.
`idempotencyKey` benzersiz; aynı anahtarla ikinci kayıt oluşmaz. Webhook işleme transaction içinde `decideWebhook` ile yapılır.

### refunds/{id} — yazma: F
`paymentId`, `kind`, `amountMinor`, `currency`, `reason`, `status: pending|succeeded|failed`, `requestedBy`, `providerRef?`, `createdAt`. Toplam iade ≤ orijinal tutar.

### events/{id} — yazma: İ (sayaçlar hariç)
`title`, `description`, `program?`, `location`, `startsAt`, `endsAt?`, `registrationDeadline`, `imagePath?`, `feeMinor` (0 = ücretsiz), `currency`, `capacity`, `reservedCount` (F), `confirmedCount` (F), `waitlistEnabled: bool`, `status: draft|published|cancelled|completed`, `donationCampaignId?`, `refundPolicy`, `organizer {name, contact}`, `createdAt`.
Kalan yer = `capacity − confirmedCount − reservedCount`. Rezervasyon süresi `app_settings/public.reservationMinutes` (öneri 15).

### event_registrations/{id} — yazma: F
`eventId`, `userId`, `participant {name, email, phone?}`, `status: reserved|confirmed|waitlisted|cancelled|expired|refunded`, `paymentId?`, `reservedUntil?`, `waitlistPosition?`, `createdAt`, `confirmedAt?`.
Akış: reserve (transaction: kontenjan kontrol + `reservedCount++`) → ödeme → webhook succeeded → `confirmed` (`reservedCount--`, `confirmedCount++`) ; süre dolarsa `expired` ve bekleme listesinden sıradaki bildirilir.

### projects/{id} — yazma: İ
`title`, `description`, `leadName`, `status: ongoing|completed|draft`, `startDate`, `endDate?`, `goals`, `verifiedResults?`, `imagePaths[]`, `campaignId?`.

### news/{id}, announcements/{id} — yazma: İ
`title`, `body`, `category`, `imagePath?`, `published: bool`, `publishedAt?`, `authorId`, `pinned?` (announcements).

### notifications/{id} — oluşturma: F, kullanıcı yalnızca `read` alanını günceller
`userId`, `type: event_new|event_reminder|registration_confirmed|payment_result|due_reminder|due_paid|donation_confirmed|campaign|announcement`, `title`, `body` (hassas tutar içermez), `data {route, refId}`, `read: bool`, `createdAt`.

### audit_logs/{id} — yazma: F, okuma: system_admin
`actorId`, `actorRole`, `action` (ör. `payment.manual_record`, `refund.issue`, `role.assign`, `export.financial`), `targetType`, `targetId`, `before?`, `after?` (kişisel/hassas veri içermez), `createdAt`. Değiştirilemez.

### app_settings/{id} — okuma: `public` herkese, diğerleri system_admin; yazma: system_admin
`public`: `clubName`, `logoPath?`, `contact`, `social`, `reservationMinutes`, `donationQuickAmountsMinor: [25000, 50000, 100000, 250000]`, `partialDuesEnabled`, `recurringDonationEnabled` (varsayılan false), `paymentMode: simulation|live`.
`system`: sağlayıcı yapılandırma durumu (gizli anahtar BURADA DEĞİL; Secret Manager).

### report_aggregates/{id} (yeni, Aşama 5/9) — yazma: F, okuma: finance
Günlük/aylık önceden toplanmış tutarlar: `period`, `kind`, `collectedMinor`, `refundedMinor`, `count`, `currency`. Yönetim paneli raporları buradan okunur; bağış/aidat/etkinlik ayrı satırlardır, birbirine karıştırılmaz.

## Callable/HTTP function sözleşmesi (isimler sabit)

| Function | Çağıran | Özet |
|---|---|---|
| `requestMembership` | kullanıcı | club_members kaydı (pending) |
| `approveMembership` | system_admin | status=active + claim |
| `assignRole` | system_admin | claim + audit |
| `createDue` / `assignDues` | finance | borç oluşturma |
| `startPayment` | kullanıcı/misafir | kind+refId → sunucu tutarı belirler, payment+oturum döner (istemci tutar GÖNDERMEZ, bağış hariç: min/max doğrulanır) |
| `paymentWebhook` (HTTP) | sağlayıcı | imza doğrula, idempotent işle |
| `reconcilePending` (zamanlı) | sistem | bekleyen ödemeleri sorgula |
| `recordManualPayment` | finance | manual=true, audit |
| `issueRefund` | finance | refunds + payments güncelle + audit |
| `reserveEventSpot` / `cancelRegistration` | kullanıcı | transaction'lı kontenjan |
| `expireReservations` (zamanlı) | sistem | süresi dolanları serbest bırak, bekleme listesi |
| `getDonationReceipt` | kullanıcı/misafir | makbuz/ödeme belgesi |
| `exportReport` | finance | yetki + audit + CSV |
| `requestAccountDeletion` | kullanıcı | KVKK silme süreci |

## Gerekli bileşik indeksler
Bkz. `firebase/firestore.indexes.json`. Yeni sorgu eklenirse indeks aynı commit'e eklenir.
