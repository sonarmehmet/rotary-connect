/// Arama için Türkçe duyarlı sadeleştirme: "İstanbul", "ISTANBUL" ve
/// "istanbul" aynı şekilde eşleşir; ç/ğ/ı/ö/ş/ü aksansız karşılıklarına iner.
String foldTr(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final ch = String.fromCharCode(rune);
    buffer.write(_fold[ch] ?? ch.toLowerCase());
  }
  return buffer.toString();
}

const Map<String, String> _fold = {
  'İ': 'i',
  'I': 'i',
  'ı': 'i',
  'Ç': 'c',
  'ç': 'c',
  'Ğ': 'g',
  'ğ': 'g',
  'Ö': 'o',
  'ö': 'o',
  'Ş': 's',
  'ş': 's',
  'Ü': 'u',
  'ü': 'u',
};
