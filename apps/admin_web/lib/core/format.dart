import 'package:rotary_shared/shared.dart';

/// Firestore'da zaman UTC `Timestamp` olarak tutulur; gösterim Europe/Istanbul
/// (UTC+3, 2016'dan beri yaz saati uygulaması yok).
const Duration istanbulOffset = Duration(hours: 3);

/// Anı İstanbul duvar saatine çevirir (dönen değerin alanları İstanbul saatidir).
DateTime toIstanbul(DateTime instant) => instant.toUtc().add(istanbulOffset);

/// İstanbul takvimine göre verilen tarih/saatin UTC karşılığı.
/// `...Date` alanları bu şekilde "İstanbul gün başlangıcı" olarak saklanır.
DateTime istanbulToInstant(int year, int month, int day,
    [int hour = 0, int minute = 0]) {
  return DateTime.utc(year, month, day, hour, minute).subtract(istanbulOffset);
}

String _two(int value) => value.toString().padLeft(2, '0');

/// Takvim tarihi (yalnızca yıl/ay/gün kullanılır): "05.03.2026".
String formatCivilDate(DateTime civil) =>
    '${_two(civil.day)}.${_two(civil.month)}.${civil.year}';

/// "05.03.2026" (İstanbul saatiyle). `null` için "—".
String formatDate(DateTime? instant) =>
    instant == null ? '—' : formatCivilDate(toIstanbul(instant));

/// "05.03.2026 14:30" (İstanbul saatiyle). `null` için "—".
String formatDateTime(DateTime? instant) {
  if (instant == null) return '—';
  final d = toIstanbul(instant);
  return '${formatCivilDate(d)} ${_two(d.hour)}:${_two(d.minute)}';
}

/// Kuruş cinsinden tutarı Türkçe gösterir: "1.250,50 ₺".
String moneyText(int minor, {String currency = 'TRY'}) =>
    Money(minor, currency: currency).format();

/// Form alanı için sembolsüz tutar: 125050 -> "1.250,50".
String moneyInput(int minor) => moneyText(minor).replaceAll(' ₺', '');

const List<String> _monthsTr = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];

/// "yyyy-MM" dönem anahtarı (İstanbul ayı).
String periodOf(DateTime instant) {
  final d = toIstanbul(instant);
  return '${d.year}-${_two(d.month)}';
}

/// "2026-10" -> "Ekim 2026". Tanınmayan biçim olduğu gibi döner.
String periodLabelTr(String period) {
  final parts = period.split('-');
  if (parts.length != 2) return period;
  final month = int.tryParse(parts[1]);
  if (month == null || month < 1 || month > 12) return period;
  return '${_monthsTr[month - 1]} ${parts[0]}';
}

/// İstanbul takvim günlerine göre kapalı tarih aralığı.
/// `start` ve `end` yalnızca yıl/ay/gün olarak yorumlanır.
class DateRange {
  const DateRange(this.start, this.end);

  final DateTime start;
  final DateTime end;

  static int _dayKey(DateTime civil) =>
      civil.year * 10000 + civil.month * 100 + civil.day;

  /// Verilen an (İstanbul gününe göre) aralıkta mı?
  bool contains(DateTime instant) {
    final key = _dayKey(toIstanbul(instant));
    return key >= _dayKey(start) && key <= _dayKey(end);
  }

  String get label => '${formatCivilDate(start)} – ${formatCivilDate(end)}';

  @override
  bool operator ==(Object other) =>
      other is DateRange &&
      _dayKey(other.start) == _dayKey(start) &&
      _dayKey(other.end) == _dayKey(end);

  @override
  int get hashCode => Object.hash(_dayKey(start), _dayKey(end));
}
