# Rotary Connect — İlerleme Günlüğü

> Birden fazla Claude hesabı bu depoda sırayla çalışır. Her oturum BAŞLAMADAN önce bu dosyayı,
> bitirmeden önce de güncellemelidir. Kaynak doğruluk burasıdır; sohbet hafızası paylaşılmaz.

## Durum özeti

| Aşama | Durum |
|---|---|
| 1 Analiz ve tasarım | ✅ Onaylandı (kullanıcı "Başla" dedi) |
| 2 Proje iskeleti | ✅ Tamamlandı — Flutter doğrulaması KULLANICI makinesinde bekliyor |
| 3 UI/UX geliştirmesi | ⏳ A (mobil) ve B (admin) çalışıyor |
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
Ayrıca `firebase/firestore.rules` emülatörle henüz test edilmedi (Aşama 10'da `tests/rules/` eklenecek).

## Sıradaki iş (Aşama 3)

1. Mobil: ana sayfa kartları (kampanya, etkinlik, proje, haber), bağış akışı ekranları, etkinlik kartı/detay, aidat ekranı, giriş/kayıt formları, yüklenme/boş/hata durumları. Tüm örnek veri `TestDataBanner` ile işaretli.
2. Admin web: Genel Bakış ve ilk liste/form ekranları.

## Kilitler (çalışmaya başlamadan önce yaz, bitince sil)

| Hesap | Dal | Klasör/modül | Başlangıç |
|---|---|---|---|
| B | b/admin-tables | apps/admin_web | 2026-10-29 |
| C | c/backend-core | functions, firebase, tests | 2026-10-29 |

## Değişiklik istekleri (şema/shared için Hesap A'ya)

| Tarih | İsteyen | İstek | Durum |
|---|---|---|---|
| — | — | — | — |

## Oturum kayıtları

- 2026-10-29 (hesap 1): Aşama 1 planı, Aşama 2 iskeleti, Firestore/Storage kuralları, functions çekirdeği.
- 2026-10-29 (hesap 1): GitHub deposu bağlandı (sonarmehmet/rotary-connect). `DATA_MODEL.md` ve `TASKS.md` yazıldı; `report_aggregates` kuralı eklendi. Dalga 1 başlayabilir: A=mobil, B=admin, C=backend. Depo şu an public; iş bitince private yapılacak.
- 2026-10-30 (hesap C): Backend çekirdeği (saf iş mantığı, DB'den bağımsız): etkinlik kontenjanı/rezervasyon/bekleme listesi/süre dolumu (`functions/src/events`), aidat durumu ve kısmi ödeme (`dues`), iade planı, sunucu tarafı tutar çözümleme, manuel ödeme, denetim kaydı temizleme. Bellek içi iyimser transaction deposu ile EŞZAMANLI kontenjan testi dahil 89 test geçti (yerel test çatısı; vitest ağ nedeniyle kurulamadı). Ayrıca: `startPayment` (idempotent, canlı modda simülasyon engeli), `processWebhook` (imza, idempotency, tutar uyuşmazlığı işareti, sıra bozukluğu), `reconcilePending`, rapor toplamları (`reports/aggregates.ts`: bağış/aidat/etkinlik ayrı, simülasyon hariç), üyelik talebi/onayı, toplu aidat atama, bildirim üreticileri (tutar/ad içermez), KVKK silme planı ve anonimleştirme.
  - DOĞRULANMAMIŞ (C): `firebase-admin`/`firebase-functions` kurulmadı (ağ yok); Firestore transaction adaptörü (`Tx` arayüzünün gerçek uygulaması), callable/HTTP sarmalayıcılar (`src/handlers/`), webhook imza doğrulama, zamanlanmış işler, `tests/rules/` emülatör testleri HENÜZ YOK. İlk olarak ağ erişimli makinede `cd functions && npm install && npm test` ile vitest'te koşturulmalı.
  - Sıradaki (C), ağ erişimli makine gerektirir: (1) `npm install` + vitest ile bu paketi koştur; (2) `firebase-admin`/`firebase-functions` ekle; (3) `src/adapters/firestore*.ts`: `Tx`/`PaymentTx` arayüzlerinin Firestore transaction uygulaması; (4) `src/handlers/`: callable/HTTP sarmalayıcılar (rol claim'i `request.auth.token.role` → `requireRole`; hata `DomainError.code` → `HttpsError`); (5) `tests/rules/` emülatör testleri; (6) sağlayıcı webhook imza doğrulaması Aşama 8'de.
  - Notlar (C → A/B): İstemciye dönen hata kodları `DomainError.code` (+ `reason`) sözleşmesidir; `reason` listesi için `functions/src` içinde `grep -rn "DomainError("`. Kontenjan reason'ları: `sold_out`, `deadline_passed`, `event_not_open`, `already_registered`.
