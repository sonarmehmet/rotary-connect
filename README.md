# Rotary Connect

Rotary kulüpleri için mobil uygulama (Flutter) + web yönetim paneli (Flutter Web) + Firebase backend.

```
apps/mobile       Flutter mobil uygulama
apps/admin_web    Flutter Web yönetim paneli
packages/shared   Ortak saf Dart: Money, roller/izinler, ödeme durum makinesi, marka renkleri
functions         Cloud Functions (TypeScript): ödeme durum makinesi, sağlayıcı arayüzü, rol kontrolü
firebase          Firestore/Storage kuralları ve indeksler
docs              İlerleme günlüğü, kararlar, devir istemi
tests             Uçtan uca ve kural testleri (Aşama 10)
```

## İlk kurulum

Flutter SDK ve Node 22 gerekir (Firebase CLI Aşama 4'ten itibaren).

```bash
cd packages/shared && dart pub get && dart test
cd ../../apps/mobile && flutter create --org com.rotaryconnect --project-name rotary_mobile . && flutter pub get && flutter analyze && flutter test
cd ../admin_web && flutter create --platforms web --project-name rotary_admin_web . && flutter pub get && flutter analyze && flutter test
cd ../../functions && npm install && npm test
```

`flutter create .` yalnızca eksik platform klasörlerini üretir; mevcut `lib/` dosyalarının üzerine yazmaz.

Çalıştırma (simülasyon modu varsayılandır; gerçek tahsilat yapılmaz):
`flutter run --dart-define=APP_ENV=dev --dart-define=PAYMENT_MODE=simulation`

## Önemli

- Ödeme sağlayıcısı henüz seçilmedi: tüm ödemeler **simülasyondur**.
- Hukuki metinler (KVKK, gizlilik, iade) hukuk danışmanı ve mali müşavir onayı gerektirir.
- Çoklu hesapla geliştirme için `docs/AGENT_PROMPT.md` ve `docs/PROGRESS.md` dosyalarına bakın.

## Hızlı çalıştırma (örnek veriyle, Firebase gerekmez)
```
cd apps/admin_web && flutter pub get && flutter run -d chrome   # yönetim paneli
cd apps/mobile    && flutter pub get && flutter run -d chrome   # mobil uygulama (veya telefon/emülatör)
```
Gerçek Firebase için: `flutterfire configure`, sonra `flutter run -t lib/main_firebase.dart`.
