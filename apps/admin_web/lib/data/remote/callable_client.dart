import '../../core/admin_exception.dart';

/// Firebase'den bağımsız callable istemci arayüzü. Dalga 2'de
/// `cloud_functions` paketiyle uygulanır: `FirebaseFunctions.instance
/// .httpsCallable(name).call(data)`; hata olursa [callableErrorToException]
/// ile `AdminException`a çevrilir. Böylece ekranlar ve testler SDK'ya bağlı değildir.
abstract class CallableClient {
  /// `data` yalnızca JSON'a uygun değerler içerir (num, String, bool, List, Map, null).
  /// Hata durumunda [AdminException] FIRLATIR.
  Future<Map<String, Object?>> call(String name, Map<String, Object?> data);
}

const Set<String> _knownCodes = {
  'unauthenticated',
  'permission-denied',
  'invalid-argument',
  'failed-precondition',
  'already-exists',
  'not-found',
  'unavailable',
  'internal',
};

/// `FirebaseFunctionsException(code, message, details)` → [AdminException].
/// Sunucu `HttpsError(code, message, {reason})` fırlatır (callableError.ts);
/// `details` içindeki `reason` taşınır. Bilinmeyen kod `internal` olur ve
/// ham mesaj kullanıcıya GÖSTERİLMEZ (iç ayrıntı sızıntısı).
AdminException callableErrorToException(
  String code,
  String? message,
  Object? details,
) {
  final known = _knownCodes.contains(code) ? code : 'internal';
  String? reason;
  if (details is Map) {
    final r = details['reason'];
    if (r is String && r.isNotEmpty) reason = r;
  }
  return AdminException(
    known,
    known == 'internal' ? null : message,
    reason,
  );
}
