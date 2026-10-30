/// Functions → istemci hata sözleşmesi (docs/TASKS.md "Entegrasyon sözleşmeleri"):
/// `permission-denied`, `invalid-argument`, `failed-precondition`,
/// `already-exists`, `unavailable`.
class AdminException implements Exception {
  const AdminException(this.code, [this.message]);

  final String code;

  /// Türkçe, kullanıcıya gösterilebilir ayrıntı (isteğe bağlı).
  final String? message;

  @override
  String toString() => 'AdminException($code)';
}

/// Hata kodunu Türkçe kullanıcı mesajına eşler. Sunucu iç ayrıntıları gösterilmez.
String errorMessageTr(Object error) {
  if (error is AdminException) {
    switch (error.code) {
      case 'permission-denied':
        return 'Bu işlem için yetkiniz yok.';
      case 'invalid-argument':
        return error.message ?? 'Girilen bilgiler geçersiz.';
      case 'failed-precondition':
        return error.message ?? 'İşlem şu anki durumda yapılamıyor.';
      case 'already-exists':
        return error.message ?? 'Bu işlem zaten kaydedilmiş.';
      case 'unavailable':
        return 'Sunucuya şu an ulaşılamıyor. Lütfen tekrar deneyin.';
    }
  }
  return 'Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.';
}
