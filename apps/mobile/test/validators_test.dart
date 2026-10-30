import 'package:flutter_test/flutter_test.dart';
import 'package:rotary_mobile/data/validators.dart';

void main() {
  test('e-posta', () {
    expect(Validators.email('a@b.co'), isNull);
    expect(Validators.email('a@b'), isNotNull);
    expect(Validators.email(''), isNotNull);
  });
  test('şifre en az 8', () {
    expect(Validators.password('1234567'), isNotNull);
    expect(Validators.password('12345678'), isNull);
  });
  test('tutar: TL biçimi, alt ve üst sınır', () {
    expect(Validators.amount('100'), isNull);
    expect(Validators.amount('1.250,50'), isNull);
    expect(Validators.amount('5'), isNotNull); // 10 TL altı
    expect(Validators.amount('abc'), isNotNull);
    expect(Validators.amount('0'), isNotNull);
  });
}
