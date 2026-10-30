import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rotary_shared/shared.dart';

import 'auth/login_page.dart';
import 'auth/session.dart';
import 'core/role_provider.dart';
import 'data/providers.dart';
import 'data/remote/admin_callables.dart';
import 'data/remote/firebase_admin_repository.dart';
import 'data/remote/firebase_callable_client.dart';
import 'main.dart';

/// Gerçek (Firebase) giriş noktası. Yapılandırma derleme zamanında verilir
/// (gizli değil ama depoya konmaz):
///
/// flutter run -d chrome -t lib/main_firebase.dart \
///   --dart-define=FIREBASE_API_KEY=... --dart-define=FIREBASE_APP_ID=... \
///   --dart-define=FIREBASE_PROJECT_ID=... --dart-define=FIREBASE_AUTH_DOMAIN=... \
///   --dart-define=FIREBASE_SENDER_ID=...
///
/// DOĞRULANMAMIŞ: derlenmedi/çalıştırılmadı. Örnek veri modu `main.dart`'tır.
const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
const _appId = String.fromEnvironment('FIREBASE_APP_ID');
const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
const _authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
const _senderId = String.fromEnvironment('FIREBASE_SENDER_ID');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_apiKey.isEmpty || _appId.isEmpty || _projectId.isEmpty) {
    runApp(const _ConfigMissingApp());
    return;
  }
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: _apiKey,
      appId: _appId,
      projectId: _projectId,
      authDomain: _authDomain,
      messagingSenderId: _senderId,
    ),
  );
  runApp(
    ProviderScope(
      overrides: [
        adminRoleProvider.overrideWith(
          (ref) =>
              ref.watch(sessionProvider).valueOrNull?.role ?? AppRole.visitor,
        ),
        adminUserIdProvider.overrideWith(
          (ref) => ref.watch(sessionProvider).valueOrNull?.uid ?? '',
        ),
        adminSignOutProvider.overrideWith(
          (ref) => () => FirebaseAuth.instance.signOut(),
        ),
        adminRepositoryProvider.overrideWith(
          (ref) => FirebaseAdminRepository(
            callables: AdminCallables(FirebaseCallableClient()),
            actorId: ref.watch(sessionProvider).valueOrNull?.uid ?? '',
          ),
        ),
      ],
      child: const _AuthGate(),
    ),
  );
}

/// Oturum yoksa giriş, personel değilse bilgi ekranı, aksi halde panel.
class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return session.when(
      loading: () => const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      error: (_, __) => const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Oturum bilgisi okunamadı. Sayfayı yenileyin.')),
        ),
      ),
      data: (s) {
        if (s == null) return const MaterialApp(home: LoginPage());
        if (!s.isStaff) return const MaterialApp(home: _NotStaffPage());
        return const AdminApp();
      },
    );
  }
}

class _NotStaffPage extends StatelessWidget {
  const _NotStaffPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Bu hesabın yönetim paneli yetkisi yok.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: refreshSession,
                child: const Text('Yetkiyi yenile'),
              ),
              TextButton(
                onPressed: () => FirebaseAuth.instance.signOut(),
                child: const Text('Çıkış yap'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfigMissingApp extends StatelessWidget {
  const _ConfigMissingApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Firebase yapılandırması eksik. --dart-define ile '
              'FIREBASE_API_KEY, FIREBASE_APP_ID ve FIREBASE_PROJECT_ID verin '
              '(bkz. lib/main_firebase.dart).',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
