import 'package:flutter_test/flutter_test.dart';
import 'package:rotary_admin_web/data/donation_record.dart';
import 'package:rotary_shared/shared.dart';

DonationRecord d({bool anonymous = false, bool simulated = false, PaymentStatus status = PaymentStatus.succeeded, String? email = 'ayse@example.com'}) =>
    DonationRecord(
      id: 'd1',
      paymentId: 'p1',
      amountMinor: 10000,
      status: status,
      donorName: 'Ayşe Yılmaz',
      donorEmail: email,
      anonymous: anonymous,
      simulated: simulated,
      createdAt: DateTime(2026, 10, 30),
    );

void main() {
  test('anonim bağışçının adı ve e-postası gizlenir', () {
    expect(d(anonymous: true).displayName, 'Anonim bağışçı');
    expect(d(anonymous: true).displayEmail, '—');
  });

  test('e-posta maskelenir', () {
    expect(d().displayEmail, 'a***@example.com');
    expect(d(email: null).displayEmail, '—');
  });

  test('kampanya toplamına yalnızca başarılı ve simülasyon olmayan bağış girer', () {
    expect(d().countsTowardTotal, isTrue);
    expect(d(simulated: true).countsTowardTotal, isFalse);
    expect(d(status: PaymentStatus.failed).countsTowardTotal, isFalse);
    expect(d(status: PaymentStatus.pending).countsTowardTotal, isFalse);
  });
}
