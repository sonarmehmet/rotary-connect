import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rotary_shared/shared.dart';

/// Oturum: kimlik + rol. Rolün kaynağı Auth custom claim `role`'dür; arayüzdeki
/// kontroller yalnızca kullanıcı deneyimidir, asıl yetki sunucudadır.
class AdminSession {
  const AdminSession({required this.uid, required this.email, required this.role});

  final String uid;
  final String? email;
  final AppRole role;

  /// Panele girebilen roller (üye/ziyaretçi/kayıtlı kullanıcı giremez).
  bool get isStaff =>
      role == AppRole.contentManager ||
      role == AppRole.financeManager ||
      role == AppRole.systemAdmin;
}

/// Claim'den rol çözer; claim yoksa `registered_user` (sunucu/kurallarla aynı varsayılan).
AppRole roleFromClaims(Map<String, dynamic>? claims) {
  final v = claims?['role'];
  if (v is! String) return AppRole.registeredUser;
  return AppRole.fromWire(v);
}

/// Oturum akışı. `idTokenChanges` rol claim'i yenilenince de tetiklenir.
final sessionProvider = StreamProvider<AdminSession?>((ref) {
  return FirebaseAuth.instance.idTokenChanges().asyncMap((user) async {
    if (user == null) return null;
    final token = await user.getIdTokenResult();
    return AdminSession(
      uid: user.uid,
      email: user.email,
      role: roleFromClaims(token.claims),
    );
  });
});

/// Rol claim'i yeni atandıysa token'ı zorla yeniler (çıkış-giriş gerektirmez).
Future<void> refreshSession() async {
  await FirebaseAuth.instance.currentUser?.getIdToken(true);
}

String signInErrorTr(Object e) {
  if (e is FirebaseAuthException) {
    switch (e.code) {
      case 'invalid-email':
        return 'E-posta adresi geçersiz.';
      case 'user-disabled':
        return 'Bu hesap devre dışı bırakılmış.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'E-posta veya parola hatalı.';
      case 'too-many-requests':
        return 'Çok fazla deneme yapıldı. Lütfen biraz bekleyin.';
      case 'network-request-failed':
        return 'Ağ bağlantısı kurulamadı.';
    }
  }
  return 'Giriş yapılamadı. Lütfen tekrar deneyin.';
}
