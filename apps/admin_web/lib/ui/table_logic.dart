import '../core/format.dart';
import '../core/text.dart';

/// Tablo sorgusu: arama + filtreler + tarih aralığı + sıralama.
/// Saf Dart; arayüzden bağımsız test edilir.
///
/// - Arama Türkçe duyarlıdır ([foldTr]).
/// - `range` verilmişse `dateOf` boş dönen veya aralık dışındaki satırlar elenir.
/// - `compare` verilmişse sıralanır (`ascending=false` ise ters).
List<T> queryRows<T>({
  required List<T> rows,
  String search = '',
  String Function(T row)? searchText,
  List<bool Function(T row)>? predicates,
  DateRange? range,
  DateTime? Function(T row)? dateOf,
  int Function(T a, T b)? compare,
  bool ascending = true,
}) {
  final needle = foldTr(search.trim());
  final tests = predicates ?? <bool Function(T row)>[];
  final out = <T>[];
  for (final row in rows) {
    if (needle.isNotEmpty &&
        searchText != null &&
        !foldTr(searchText(row)).contains(needle)) {
      continue;
    }
    var passes = true;
    for (final test in tests) {
      if (!test(row)) {
        passes = false;
        break;
      }
    }
    if (!passes) continue;
    if (range != null && dateOf != null) {
      final at = dateOf(row);
      if (at == null || !range.contains(at)) continue;
    }
    out.add(row);
  }
  if (compare != null) {
    out.sort((a, b) => ascending ? compare(a, b) : compare(b, a));
  }
  return out;
}

/// Sayfa sayısı (en az 1; boş liste de tek boş sayfadır).
int pageCount(int total, int pageSize) {
  if (total <= 0 || pageSize <= 0) return 1;
  return (total + pageSize - 1) ~/ pageSize;
}
