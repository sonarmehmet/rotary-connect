# Yayın rehberi (Android, iOS, Web)

Durum: kod ve platform klasörleri depoda. **Hiçbiri henüz gerçek Firebase'e bağlı yayın için doğrulanmadı**; bu rehber kurulumun sırasını verir. Gizli dosyalar (`google-services.json`, `GoogleService-Info.plist`, `key.properties`, `*.jks`) depoya KONMAZ.

## 0. Hızlı deneme (kurulumsuz)
GitHub → Actions → **build-apps** → Run workflow. Çıktılar:
- `admin-web`: yönetim paneli (Firebase sırları yoksa ÖRNEK VERİ).
- `mobile-android-apk`: debug anahtarıyla imzalı APK (telefona kurulabilir; Play Store için değil).
- `mobile-ios-unsigned`: imzasız `Runner.app` (cihaza kurmak için Xcode + Apple hesabı şart).

## 1. Firebase projesi (bir kez)
1. console.firebase.google.com → proje oluştur; Authentication (E-posta/Parola), Firestore, Functions, Storage, Hosting aç. Functions için Blaze planı gerekir.
2. `npm i -g firebase-tools && firebase login && firebase use --add` (`.firebaserc` depoya girmez).
3. `firebase deploy --only firestore,storage,functions`.
4. İlk sistem yöneticisi: Auth'ta kullanıcı oluştur, sonra Admin SDK ile claim ata (`setCustomUserClaims(uid, {role:'system_admin'})`; tek seferlik betik). Sonrası paneldeki "Rol ve İzinler" ekranından yapılır.

## 2. Web (yönetim paneli)
Firebase konsolunda Web uygulaması ekle; `apiKey`, `appId`, `projectId`, `authDomain`, `messagingSenderId` değerlerini al.
```
cd apps/admin_web
flutter pub get
flutter build web --release -t lib/main_firebase.dart \
  --dart-define=FIREBASE_API_KEY=... --dart-define=FIREBASE_APP_ID=... \
  --dart-define=FIREBASE_PROJECT_ID=... --dart-define=FIREBASE_AUTH_DOMAIN=... \
  --dart-define=FIREBASE_SENDER_ID=...
cd ../.. && firebase deploy --only hosting
```
`firebase.json` Hosting ayarı hazırdır (SPA yönlendirmesi, arama motoru dışı, iframe yasağı). Panel dışarıdan indekslenmez.

## 3. Android (mobil)
1. Paket adı: `com.rotaryconnect.rotary_mobile` (değiştirecekseniz `android/app/build.gradle.kts` + Firebase kaydı birlikte).
2. Firebase'e Android uygulaması ekle → `flutterfire configure` (FlutterFire CLI) `firebase_options.dart` ve gradle ayarlarını üretir. **Mobil kod henüz Firebase'e bağlı değil (A/C işi); bu adım bağlantı kodu yazıldıktan sonra.**
3. Yayın anahtarı: `keytool -genkey -v -keystore ~/rotary-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
4. `apps/mobile/android/key.properties` (commit edilmez):
```
storeFile=/tam/yol/rotary-upload.jks
storePassword=...
keyAlias=upload
keyPassword=...
```
5. `flutter build appbundle --release` → `build/app/outputs/bundle/release/app-release.aab` → Play Console'a yükle. Bildirimler (Android 13+) için `POST_NOTIFICATIONS` izni manifestte tanımlı.

## 4. iOS (mobil) — Mac + Apple Developer hesabı (yıllık ücretli) gerekir
1. `cd apps/mobile && flutter pub get && cd ios && pod install`
2. Xcode'da `ios/Runner.xcworkspace` aç → Signing & Capabilities: Team seç; Bundle Identifier `com.rotaryconnect.rotaryMobile` (değiştirilebilir).
3. Bildirimler için Capabilities: Push Notifications + Background Modes (Remote notifications); APNs anahtarını Firebase'e yükle.
4. `flutter build ipa --release` → Xcode Organizer/Transporter ile TestFlight/App Store.

## 5. Mağaza öncesi (kod dışı)
KVKK aydınlatma, gizlilik politikası, iade/mesafeli satış metinleri (hukuk onayı), uygulama ikonları/ekran görüntüleri, canlı ödeme (iyzico sırları ve test), `app_settings/public.paymentMode` canlıya alma.
