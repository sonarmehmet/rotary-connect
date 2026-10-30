import 'package:rotary_shared/shared.dart';

/// Form doğrulayıcıları (saf fonksiyonlar, test edilebilir). Hata metni null ise geçerli.
abstract final class Validators {
  static final RegExp _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  static String? required(String? v, [String label = 'Bu alan']) =>
      (v == null || v.trim().isEmpty) ? '$label zorunlu' : null;

  static String? email(String? v) {
    if (v == null || v.trim().isEmpty) return 'E-posta zorunlu';
    return _email.hasMatch(v.trim()) ? null : 'Geçerli bir e-posta girin';
  }

  static String? password(String? v) {
    if (v == null || v.length < 8) return 'Şifre en az 8 karakter olmalı';
    return null;
  }

  /// Tutar: TL biçiminde (örn. 1.250,50). [min] ve [max] küçük birim cinsinden.
  static String? amount(String? v, {int min = 1000, int max = 100000000}) {
    final m = Money.tryParseTr(v ?? '');
    if (m == null || m.minor <= 0) return 'Geçerli bir tutar girin';
    if (m.minor < min) return 'En az ${Money(min).format()} bağış yapılabilir';
    if (m.minor > max) return 'Tutar çok yüksek';
    return null;
  }
}
