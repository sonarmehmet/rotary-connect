import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'data/firebase_app_repository.dart';
import 'data/providers.dart';
import 'data/repository.dart';

/// Gerçek (Firebase) giriş noktası. Yapılandırma iki yoldan verilir:
/// 1) Önerilen: `flutterfire configure` (android/ios dosyalarını üretir) → `flutter run -t lib/main_firebase.dart`
/// 2) Ya da `--dart-define=FIREBASE_API_KEY=... FIREBASE_APP_ID=... FIREBASE_PROJECT_ID=... FIREBASE_SENDER_ID=...`
/// Emülatör: `--dart-define=USE_EMULATOR=true` (Android emülatörde `EMULATOR_HOST=10.0.2.2`).
/// DOĞRULANMAMIŞ: gerçek projede çalıştırılmadı. Örnek veri modu `main.dart`'tır.
const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
const _appId = String.fromEnvironment('FIREBASE_APP_ID');
const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
const _senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
const _useEmulator = bool.fromEnvironment('USE_EMULATOR');
const _emulatorHost = String.fromEnvironment('EMULATOR_HOST', defaultValue: 'localhost');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('tr_TR');
  if (_apiKey.isNotEmpty && _appId.isNotEmpty && _projectId.isNotEmpty) {
    await Firebase.initializeApp(
      options: const FirebaseOptions(apiKey: _apiKey, appId: _appId, projectId: _projectId, messagingSenderId: _senderId),
    );
  } else {
    // Yerel yapılandırma dosyaları (google-services.json / GoogleService-Info.plist) kullanılır.
    await Firebase.initializeApp();
  }
  if (_useEmulator) {
    await FirebaseAuth.instance.useAuthEmulator(_emulatorHost, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(_emulatorHost, 8080);
    FirebaseFunctions.instanceFor(region: 'europe-west1').useFunctionsEmulator(_emulatorHost, 5001);
  }

  final container = ProviderContainer(
    overrides: [repositoryProvider.overrideWith((ref) => FirebaseAppRepository())],
  );
  await container.read(sessionProvider.notifier).restore(); // kalıcı oturumu geri yükle
  runApp(UncontrolledProviderScope(container: container, child: const RotaryConnectApp()));
}
