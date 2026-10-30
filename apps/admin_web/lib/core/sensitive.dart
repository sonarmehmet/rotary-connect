/// Bildirim/duyuru metninde bulunamayacak içerik. Kurallar sunucudaki
/// `containsSensitive` (functions/src/handlers/announce.ts) ile AYNI olmalıdır;
/// istemci denetimi yalnızca erken uyarıdır, kesin denetim sunucudadır.
final List<RegExp> _sensitive = [
  RegExp(r'[^\s@]+@[^\s@]+'), // e-posta
  RegExp(r'\d(?:[ -]?\d){9,}'), // 10+ rakam: telefon, TCKN, IBAN parçası
  RegExp(r'\d[\d.,]*\s?(?:₺|tl\b|try\b|lira\b)', caseSensitive: false), // tutar
  RegExp(r'\btr\d{2}\b', caseSensitive: false), // IBAN başlangıcı
];

bool containsSensitive(String text) => _sensitive.any((re) => re.hasMatch(text));
