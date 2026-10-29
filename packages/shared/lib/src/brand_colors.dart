/// Marka renkleri (ARGB int). Flutter bağımlılığı olmaması için `Color` yerine int.
/// Kullanım: `Color(BrandColors.navy)`.
///
/// Altın rengi beyaz üzerinde düşük kontrastlıdır; metin için DEĞİL,
/// yalnızca çizgi/vurgu/ikon için kullanılmalıdır.
abstract final class BrandColors {
  static const int navy = 0xFF0B2A5B;
  static const int navyDark = 0xFF071B3D;
  static const int gold = 0xFFC9A24B;
  static const int white = 0xFFFFFFFF;
  static const int lightGray = 0xFFF3F4F6;
  static const int success = 0xFF1E8E3E;
  static const int error = 0xFFC62828;
  static const int warning = 0xFFB26A00;
}
