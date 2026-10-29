/// Para tutarı: kuruş (minor unit) cinsinden TAM SAYI + para birimi.
/// Kayan noktalı (double) tutar kullanılmaz.
class Money implements Comparable<Money> {
  const Money(this.minor, {this.currency = 'TRY'});

  /// Tam lira/ana birim değerinden oluşturur: `Money.fromMajor(250)` = 250,00 ₺.
  factory Money.fromMajor(int major, {String currency = 'TRY'}) =>
      Money(major * 100, currency: currency);

  /// Kuruş cinsinden tutar (örn. 25000 = 250,00 ₺).
  final int minor;
  final String currency;

  static final RegExp _digits = RegExp(r'^\d+$');
  static final RegExp _grouped = RegExp(r'^\d{1,3}(\.\d{3})+$');
  static final RegExp _fraction = RegExp(r'^\d{1,2}$');

  /// Türkçe biçimli girdiyi ayrıştırır: "1.250,50", "250", "250,5", "250 TL".
  /// Geçersizse `null` döner. "." yalnızca binlik ayraç olarak kabul edilir
  /// ("1.5" geçersizdir; belirsizliği önlemek için).
  static Money? tryParseTr(String input, {String currency = 'TRY'}) {
    final cleaned = input
        .trim()
        .replaceAll('₺', '')
        .replaceAll(RegExp('TL', caseSensitive: false), '')
        .replaceAll(' ', '');
    if (cleaned.isEmpty) return null;

    final parts = cleaned.split(',');
    if (parts.length > 2) return null;

    final whole = parts[0];
    final frac = parts.length == 2 ? parts[1] : '';

    String wholeDigits;
    if (_digits.hasMatch(whole)) {
      wholeDigits = whole;
    } else if (_grouped.hasMatch(whole)) {
      wholeDigits = whole.replaceAll('.', '');
    } else {
      return null;
    }
    if (parts.length == 2 && !_fraction.hasMatch(frac)) return null;

    final fracMinor = frac.isEmpty ? 0 : int.parse(frac.padRight(2, '0'));
    return Money(int.parse(wholeDigits) * 100 + fracMinor, currency: currency);
  }

  bool get isNegative => minor < 0;
  bool get isZero => minor == 0;

  Money operator +(Money other) {
    _requireSameCurrency(other);
    return Money(minor + other.minor, currency: currency);
  }

  Money operator -(Money other) {
    _requireSameCurrency(other);
    return Money(minor - other.minor, currency: currency);
  }

  bool operator <(Money other) => compareTo(other) < 0;
  bool operator <=(Money other) => compareTo(other) <= 0;
  bool operator >(Money other) => compareTo(other) > 0;
  bool operator >=(Money other) => compareTo(other) >= 0;

  void _requireSameCurrency(Money other) {
    if (currency != other.currency) {
      throw ArgumentError(
          'Para birimi uyuşmuyor: $currency ile ${other.currency}');
    }
  }

  @override
  int compareTo(Money other) {
    _requireSameCurrency(other);
    return minor.compareTo(other.minor);
  }

  /// Türkçe gösterim: "1.250,50 ₺".
  String format() {
    final abs = minor.abs();
    final whole = _group(abs ~/ 100);
    final frac = (abs % 100).toString().padLeft(2, '0');
    final sign = minor < 0 ? '-' : '';
    final symbol = currency == 'TRY' ? '₺' : currency;
    return '$sign$whole,$frac $symbol';
  }

  static String _group(int value) {
    final s = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write('.');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is Money && other.minor == minor && other.currency == currency;

  @override
  int get hashCode => Object.hash(minor, currency);

  @override
  String toString() => 'Money($minor $currency)';
}
