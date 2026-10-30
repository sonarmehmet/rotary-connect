import 'package:flutter_test/flutter_test.dart';
import 'package:rotary_admin_web/core/admin_exception.dart';
import 'package:rotary_admin_web/core/csv.dart';
import 'package:rotary_admin_web/core/format.dart';
import 'package:rotary_admin_web/core/text.dart';
import 'package:rotary_admin_web/features/settings/settings_page.dart';
import 'package:rotary_admin_web/ui/table_logic.dart';

void main() {
  group('foldTr', () {
    test('Türkçe büyük/küçük harf ve aksanlar eşleşir', () {
      expect(foldTr('İSTANBUL'), 'istanbul');
      expect(foldTr('ISPARTA'), 'isparta');
      expect(foldTr('Çağrı Şükrü Öğüt'), 'cagri sukru ogut');
    });
  });

  group('tarih ve para biçimi', () {
    test('İstanbul saati UTC+3', () {
      final instant = DateTime.utc(2026, 10, 29, 21, 30); // 30.10 00:30 İstanbul
      expect(formatDate(instant), '30.10.2026');
      expect(formatDateTime(instant), '30.10.2026 00:30');
      expect(periodOf(instant), '2026-10');
    });

    test('istanbulToInstant gün başlangıcını UTC önceki güne çevirir', () {
      final instant = istanbulToInstant(2026, 3, 5);
      expect(instant, DateTime.utc(2026, 3, 4, 21));
      expect(formatDate(instant), '05.03.2026');
    });

    test('periodLabelTr', () {
      expect(periodLabelTr('2026-10'), 'Ekim 2026');
      expect(periodLabelTr('bozuk'), 'bozuk');
    });

    test('moneyText kuruştan Türkçe biçim üretir', () {
      expect(moneyText(125050), '1.250,50 ₺');
      expect(moneyInput(125050), '1.250,50');
      expect(moneyText(0), '0,00 ₺');
    });

    test('DateRange İstanbul gününe göre kapalı aralıktır', () {
      final range = DateRange(DateTime(2026, 10, 1), DateTime(2026, 10, 31));
      expect(range.contains(istanbulToInstant(2026, 10, 1)), isTrue);
      expect(range.contains(istanbulToInstant(2026, 10, 31, 23, 59)), isTrue);
      expect(range.contains(istanbulToInstant(2026, 11, 1)), isFalse);
      expect(range.contains(istanbulToInstant(2026, 9, 30, 23, 59)), isFalse);
    });
  });

  group('CSV', () {
    test('formül enjeksiyonu etkisizleştirilir', () {
      expect(csvCell('=1+1'), "'=1+1");
      expect(csvCell('+90'), "'+90");
      expect(csvCell('@x'), "'@x");
      expect(csvCell('-abc'), "'-abc");
    });

    test('negatif sayı olduğu gibi kalır', () {
      expect(csvCell('-250'), '-250');
    });

    test('ayraç, tırnak ve satır sonu tırnaklanır', () {
      expect(csvCell('a;b'), '"a;b"');
      expect(csvCell('a"b'), '"a""b"');
      expect(csvCell('a\nb'), '"a\nb"');
    });

    test('buildCsv BOM, noktalı virgül ve CRLF kullanır', () {
      final csv = buildCsv(['a', 'b'], [
        ['1', '2'],
      ]);
      expect(csv, '﻿a;b\r\n1;2\r\n');
    });
  });

  group('tablo mantığı', () {
    final rows = ['İzmir', 'Ankara', 'Adana', 'Isparta'];

    test('Türkçe duyarlı arama', () {
      final out = queryRows<String>(
        rows: rows,
        search: 'IZMIR',
        searchText: (r) => r,
      );
      expect(out, ['İzmir']);
    });

    test('filtre ve sıralama', () {
      final out = queryRows<String>(
        rows: rows,
        predicates: [(r) => r.startsWith('A')],
        compare: (a, b) => a.compareTo(b),
      );
      expect(out, ['Adana', 'Ankara']);
      final desc = queryRows<String>(
        rows: rows,
        compare: (a, b) => a.compareTo(b),
        ascending: false,
      );
      expect(desc.first, 'İzmir');
    });

    test('tarihi olmayan satır aralık filtresinde elenir', () {
      final range = DateRange(DateTime(2026, 1, 1), DateTime(2026, 12, 31));
      final out = queryRows<DateTime?>(
        rows: [DateTime.utc(2026, 5, 5), null],
        range: range,
        dateOf: (d) => d,
      );
      expect(out.length, 1);
    });

    test('pageCount', () {
      expect(pageCount(0, 10), 1);
      expect(pageCount(10, 10), 1);
      expect(pageCount(11, 10), 2);
      expect(pageCount(30, 10), 3);
    });
  });

  group('hata eşleme', () {
    test('sözleşmedeki kodlar Türkçe mesaja eşlenir', () {
      expect(
        errorMessageTr(const AdminException('permission-denied')),
        'Bu işlem için yetkiniz yok.',
      );
      expect(
        errorMessageTr(const AdminException('failed-precondition', 'Kontenjan dolu.')),
        'Kontenjan dolu.',
      );
      expect(errorMessageTr(StateError('iç ayrıntı')), isNot(contains('iç ayrıntı')));
    });
  });

  group('hızlı bağış tutarı ayrıştırma', () {
    test('geçerli girdiler', () {
      expect(parseQuickAmounts('250; 500; 1.000'), [25000, 50000, 100000]);
      expect(parseQuickAmounts(' 250 ;'), [25000]);
    });

    test('geçersiz girdiler', () {
      expect(parseQuickAmounts(''), isNull);
      expect(parseQuickAmounts('abc'), isNull);
      expect(parseQuickAmounts('250,50'), isNull); // ondalık yok
      expect(parseQuickAmounts('250; x'), isNull);
    });
  });
}
