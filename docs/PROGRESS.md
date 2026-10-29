# Rotary Connect — İlerleme Günlüğü

> Birden fazla Claude hesabı bu depoda sırayla çalışır. Her oturum BAŞLAMADAN önce bu dosyayı,
> bitirmeden önce de güncellemelidir. Kaynak doğruluk burasıdır; sohbet hafızası paylaşılmaz.

## Durum özeti

| Aşama | Durum |
|---|---|
| 1 Analiz ve tasarım | ✅ Onaylandı (kullanıcı "Başla" dedi) |
| 2 Proje iskeleti | ✅ Tamamlandı — Flutter doğrulaması KULLANICI makinesinde bekliyor |
| 3 UI/UX geliştirmesi | ⏳ Sıradaki |
| 4 Kimlik doğrulama ve backend | ⬜ |
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

## Değişiklik istekleri (şema/shared için Hesap A'ya)

| Tarih | İsteyen | İstek | Durum |
|---|---|---|---|
| — | — | — | — |

## Oturum kayıtları

- 2026-10-29 (hesap 1): Aşama 1 planı, Aşama 2 iskeleti, Firestore/Storage kuralları, functions çekirdeği.
- 2026-10-29 (hesap 1): GitHub deposu bağlandı (sonarmehmet/rotary-connect). `DATA_MODEL.md` ve `TASKS.md` yazıldı; `report_aggregates` kuralı eklendi. Dalga 1 başlayabilir: A=mobil, B=admin, C=backend. Depo şu an public; iş bitince private yapılacak.
