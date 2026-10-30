# Rotary Connect — İlerleme Günlüğü

> Birden fazla Claude hesabı bu depoda sırayla çalışır. Her oturum BAŞLAMADAN önce bu dosyayı,
> bitirmeden önce de güncellemelidir. Kaynak doğruluk burasıdır; sohbet hafızası paylaşılmaz.

## Durum özeti

| Aşama | Durum |
|---|---|
| 1 Analiz ve tasarım | ✅ Onaylandı (kullanıcı "Başla" dedi) |
| 2 Proje iskeleti | ✅ Tamamlandı — Flutter doğrulaması KULLANICI makinesinde bekliyor |
| 3 UI/UX geliştirmesi | ⏳ B (admin): Dalga 1 ekranları yazıldı, DERLENMEDİ (aşağıya bakın); A (mobil) çalışıyor |
| 4 Kimlik doğrulama ve backend | 🟡 C: saf iş mantığı hazır (kontenjan, aidat, iade, denetim); Firebase bağlantısı bekliyor |
| 5 Aidat ve finans | ⬜ |
| 6 Bağış ve kampanyalar | ⬜ |
| 7 Etkinlikler ve kayıt | ⬜ |
| 8 Ödeme sağlayıcı entegrasyonu | ⬜ (sağlayıcı kararı bekliyor) |
| 9 Yönetim paneli | ⬜ |
| 10 Test ve kalite | ⬜ |
| 11 Teslimat ve yayın | ⬜ |

## Alınan kararlar

- Mobil: Flutter + Riverpod + GoRouter, feature-first. Web panel: **Flutter Web** (tek dil, hızlı geliştirme).
- Backend: Firebase (Auth, Firestore, Storage, FCM) + Cloud Functions (TypeScript, Node 22).
- Tutarlar kuruş cinsinden tam sayı (`amountMinor`) + `currency`. Durum makinesi Dart ve TS'de birebir aynı.
- İstemci finansal koleksiyonlara yazamaz; tüm yazmalar Functions üzerinden.
- Ödeme: `PaymentProvider` arayüzü + `SimulatedProvider`. Gerçek sağlayıcı (iyzico/PayTR adayları) Aşama 8'de, kullanıcı onayıyla.
- Rotary resmî logosu verilmedi: `BrandLogo` geçici yer tutucu.
- Hukuki metinler yalnızca taslak olacak; hukuk ve mali müşavir onayı gerekir.

## Aşama 2'de doğrulananlar

- `functions/`: TypeScript tip kontrolü geçti, 13 birim testi geçti (durum makinesi, idempotent webhook kararı, para doğrulama, roller, simülasyon sağlayıcı).
- Ortamda `npm install` ve Flutter SDK indirmesi engelliydi (ağ). Bu yüzden vitest yerine yerel bir test çatısıyla koşturuldu.

## DOĞRULANMAMIŞ (kullanıcı makinesinde çalıştırılmalı)

```
cd apps/mobile && flutter create --org com.rotaryconnect --project-name rotary_mobile . && flutter pub get && flutter analyze && flutter test
cd apps/admin_web && flutter create --platforms web --project-name rotary_admin_web . && flutter pub get && flutter analyze && flutter test
cd packages/shared && dart pub get && dart analyze && dart test
cd functions && npm install && npm test
```
Çıkan hata/uyarıları buraya ve bir sonraki oturuma bildirin; Flutter kodu elle yazıldı, derleme hatası çıkabilir.

**DOĞRULANMAMIŞ (B, 2026-10-30):** Bu ortamda Flutter/Dart SDK'ya erişilemedi (storage.googleapis.com, pub.dev, ghcr.io engelli); `apps/admin_web` altındaki TÜM yeni kod ve testler hiç derlenmedi/çalıştırılmadı. Kod elle gözden geçirildi (importlar, tipler, örnek veri ile test beklentileri tek tek karşılaştırıldı) ama `flutter analyze` ve `flutter test` sonucu bilinmiyor. Özellikle şüpheli noktalar: `DateFormField` (FormField alt sınıfı), `DropdownMenu` kullanımı diyalog içinde, `AdminTable` yatay/dikey kaydırma iç içeliği, widget testlerindeki metin eşleşmeleri (`pages_test.dart`).
Ayrıca `firebase/firestore.rules` emülatörle henüz test edilmedi (Aşama 10'da `tests/rules/` eklenecek).

## Admin web (Hesap B) durumu

Yazıldı (`apps/admin_web/lib`): `core/` (biçim/İstanbul saati, Türkçe arama, CSV, hata eşleme, etiketler), `data/` (modeller, `AdminRepository` arayüzü, `FakeAdminRepository` + örnek veri), `ui/` (`AdminTable`, form/diyalog bileşenleri, durum görünümleri, `TestDataBanner`), `features/` (overview, campaigns, events, projects, news, dues, payments, refunds, audit, reports/CSV). Testler: `test/core_test.dart`, `repository_test.dart`, `pages_test.dart`, `shell_test.dart`.
- Rol filtresi: menü + rota düzeyinde (yetkisiz rota `NoAccessView`); yazma düğmeleri izne göre gizlenir. Asıl yetki sunucudadır.
- CSV: Dalga 1'de önizleme + panoya kopyala (dosya indirme Dalga 2'de `exportReport` ile bağlanacak). Formül enjeksiyonu önlemi, `;` ayraç, UTF-8 BOM, kişisel veri yok.
- Üyeler (onay/askıya alma/istifa), Rol ve İzinler (rol atama; son sistem yöneticisi korunur; club_member yalnızca üyelik onayıyla) ve Katılımcı Kayıtları (salt okunur) eklendi; sahte depo `functions/src/members/members.ts` kurallarını taklit eder.
- Henüz placeholder: Bildirimler, Uygulama Ayarları (Dalga 2).

**Dalga 2 için notlar (B → kendim / C):**
- `report_aggregates` gerçekte GÜNLÜK satır (`day`) ve SİMÜLASYON ödemelerini DIŞLAR (`functions/src/reports/aggregates.ts`); panelin örnek `ReportAggregate` modeli aylık `period` kullanıyor ve örnek verideki simülasyon ödemelerini sayıyor. Gerçek depoda günleri aya toplayıp modele çevir; simülasyon modunda raporların boş çıkması beklenen davranıştır (arayüzde bunu açıkla).
- Sunucu hataları `DomainError.code` + `reason` taşıyor; `errorMessageTr` şu an yalnızca `code` ve isteğe bağlı mesaj eşliyor. Gerçek depoda `reason` → Türkçe metin eşlemesi eklenmeli (`sold_out`, `deadline_passed`, `event_not_open`, `already_registered`, iade/aidat reason'ları).
- İade başlatma: panel `refundableMinor = tutar − refundedMinor` ile uyarır; kesin kural sunucudadır (bekleyen iadeler de kalandan düşer; sahte depo bunu taklit eder).

## Sıradaki iş (Aşama 3)

1. Mobil: ana sayfa kartları (kampanya, etkinlik, proje, haber), bağış akışı ekranları, etkinlik kartı/detay, aidat ekranı, giriş/kayıt formları, yüklenme/boş/hata durumları. Tüm örnek veri `TestDataBanner` ile işaretli.
2. Admin web: Dalga 1 ekranları TAMAM (kodlandı, derlenmedi). Önce kullanıcı makinesinde `flutter analyze` + `flutter test` ile doğrula ve hataları düzelt; sonra Dalga 2 (gerçek veri, rol atama, üyelik onayı, iade/manuel ödeme gerçek callable, `exportReport`).

## Kilitler (çalışmaya başlamadan önce yaz, bitince sil)

| Hesap | Dal | Klasör/modül | Başlangıç |
|---|---|---|---|
| C | c/backend-core | functions, firebase, tests | 2026-10-29 |

## Değişiklik istekleri (şema/shared için Hesap A'ya)

| Tarih | İsteyen | İstek | Durum |
|---|---|---|---|
| — | — | — | — |

## Oturum kayıtları

- 2026-10-29 (hesap 1): Aşama 1 planı, Aşama 2 iskeleti, Firestore/Storage kuralları, functions çekirdeği.
- 2026-10-29 (hesap 1): GitHub deposu bağlandı (sonarmehmet/rotary-connect). `DATA_MODEL.md` ve `TASKS.md` yazıldı; `report_aggregates` kuralı eklendi. Dalga 1 başlayabilir: A=mobil, B=admin, C=backend. Depo şu an public; iş bitince private yapılacak.
- 2026-10-30 (hesap C): Backend çekirdeği (saf iş mantığı, DB'den bağımsız): etkinlik kontenjanı/rezervasyon/bekleme listesi/süre dolumu (`functions/src/events`), aidat durumu ve kısmi ödeme (`dues`), iade planı, sunucu tarafı tutar çözümleme, manuel ödeme, denetim kaydı temizleme. Bellek içi iyimser transaction deposu ile EŞZAMANLI kontenjan testi dahil 97 test geçti (yerel test çatısı; vitest ağ nedeniyle kurulamadı). Ayrıca: `startPayment` (idempotent, canlı modda simülasyon engeli), `processWebhook` (imza, idempotency, tutar uyuşmazlığı işareti, sıra bozukluğu), `reconcilePending`, rapor toplamları (`reports/aggregates.ts`: bağış/aidat/etkinlik ayrı, simülasyon hariç), üyelik talebi/onayı, toplu aidat atama, bildirim üreticileri (tutar/ad içermez), KVKK silme planı ve anonimleştirme.
  - DOĞRULANMAMIŞ (C): `firebase-admin`/`firebase-functions` kurulmadı (ağ yok); Firestore transaction adaptörü (`Tx` arayüzünün gerçek uygulaması), callable/HTTP sarmalayıcılar (`src/handlers/`), webhook imza doğrulama, zamanlanmış işler, `tests/rules/` emülatör testleri HENÜZ YOK. İlk olarak ağ erişimli makinede `cd functions && npm install && npm test` ile vitest'te koşturulmalı.
  - Firestore adaptörleri (`functions/src/adapters/`) yazıldı ve sahte Firestore ile test edildi (alan adları DATA_MODEL.md ile eşleşiyor, okuma-yazma sırası kuralı zorlanıyor; bu testle `cancelRegistration`'daki gerçek bir "yazdıktan sonra okuma" hatası bulunup düzeltildi). SDK'ya doğrudan bağlı DEĞİL: `FsDb`/`FsTx` arayüzleri üzerinden. İki yeni indeks eklendi (payments status+createdAt, event_registrations eventId+createdAt).
  - Bu oturumda npm kayıt sunucusu politika gereği engelliydi (403); `firebase-admin` hiç kurulamadı.
  - Sıradaki (C), ağ erişimli makine gerektirir: (1) `npm install` + vitest ile bu paketi koştur; (2) `firebase-admin`/`firebase-functions` ekle; (3) `src/adapters/sdk.ts`: gerçek `firebase-admin` Firestore'unu `FsDb`/`FsTx`'e saran ince sarmalayıcı (`Timestamp.fromMillis`/`toMillis` ile `Clock`); (4) `src/handlers/`: callable/HTTP sarmalayıcılar (rol claim'i `request.auth.token.role` → `requireRole`; hata `DomainError.code` → `HttpsError`); (5) `tests/rules/` emülatör testleri; (6) sağlayıcı webhook imza doğrulaması Aşama 8'de.
  - Notlar (C → A/B): İstemciye dönen hata kodları `DomainError.code` (+ `reason`) sözleşmesidir; `reason` listesi için `functions/src` içinde `grep -rn "DomainError("`. Kontenjan reason'ları: `sold_out`, `deadline_passed`, `event_not_open`, `already_registered`.
- 2026-10-30 (hesap B): Dalga 1 admin paneli: ortak `AdminTable` (arama [Türkçe duyarlı], seçenekli filtre, tarih aralığı, sıralama, sayfalama, boş/hata durumu), Genel Bakış (bağış/aidat/etkinlik ayrı kartlar, iade düşülmüş net), liste+form: Kampanyalar, Etkinlikler, Projeler, Haberler/Duyurular; liste+eylem: Aidat (borç atama, manuel ödeme), Ödemeler (iade başlat), İadeler, Denetim, Raporlar (+CSV dışa aktarma arayüzü, `exportFinancialData` bayrağıyla). Veri `AdminRepository` arayüzü + `FakeAdminRepository` (iade üst sınırı, kısmi ödeme, mükerrer işlem kuralları taklit edilir; her ekran `TestDataBanner`lı). Sayaçlar/toplamlar istemciden yazılmaz. DOĞRULANMAMIŞ: hiçbir Flutter komutu çalıştırılamadı (bkz. DOĞRULANMAMIŞ bölümü). Sıradaki (B): kullanıcı makinesinde analyze/test çıktısını düzelt → Dalga 2.
- 2026-10-30 (hesap B, 2. oturum): Üyeler, Rol ve İzinler, Katılımcı Kayıtları ekranları + sahte depo kuralları + testler. DOĞRULANMAMIŞ (Flutter yok, derlenmedi). Sıradaki (B): kullanıcı makinesinde analyze/test düzeltmeleri; Bildirimler ve Ayarlar; Dalga 2 gerçek depo.
