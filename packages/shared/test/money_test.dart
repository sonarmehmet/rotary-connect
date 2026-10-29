import 'package:rotary_shared/shared.dart';
import 'package:test/test.dart';

void main() {
  group('Money', () {
    test('fromMajor kuruşa çevirir', () {
      expect(Money.fromMajor(250).minor, 25000);
    });

    test('format Türkçe biçimde gösterir', () {
      expect(const Money(125050).format(), '1.250,50 ₺');
      expect(const Money(5).format(), '0,05 ₺');
      expect(const Money(100000000).format(), '1.000.000,00 ₺');
      expect(const Money(-2500).format(), '-25,00 ₺');
    });

    test('tryParseTr geçerli girdileri ayrıştırır', () {
      expect(Money.tryParseTr('250')?.minor, 25000);
      expect(Money.tryParseTr('1.250,50')?.minor, 125050);
      expect(Money.tryParseTr('250,5')?.minor, 25050);
      expect(Money.tryParseTr(' 500 TL ')?.minor, 50000);
      expect(Money.tryParseTr('₺2.500')?.minor, 250000);
    });

    test('tryParseTr geçersiz girdileri reddeder', () {
      for (final bad in ['', 'abc', '1.5', '1,234', '1,2,3', '12.34.5', '-5']) {
        expect(Money.tryParseTr(bad), isNull, reason: bad);
      }
    });

    test('toplama/çıkarma ve karşılaştırma', () {
      const a = Money(1000);
      const b = Money(250);
      expect((a + b).minor, 1250);
      expect((a - b).minor, 750);
      expect(a > b, isTrue);
      expect(a == const Money(1000), isTrue);
    });

    test('farklı para birimleri karıştırılamaz', () {
      expect(() => const Money(1) + const Money(1, currency: 'EUR'),
          throwsArgumentError);
    });
  });
}
