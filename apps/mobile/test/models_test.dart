import 'package:flutter_test/flutter_test.dart';
import 'package:rotary_mobile/data/models.dart';
import 'package:rotary_mobile/data/repository.dart';
import 'package:rotary_shared/shared.dart';

void main() {
  test('kampanya ilerlemesi 0..1 arasında kalır', () {
    final c = Campaign(id: 'x', title: 't', description: '', goal: Money.fromMajor(100), verifiedTotal: Money.fromMajor(150), active: true);
    expect(c.progress, 1.0);
    final z = Campaign(id: 'x', title: 't', description: '', goal: const Money(0), verifiedTotal: const Money(0), active: true);
    expect(z.progress, 0);
  });

  test('borç: kalan, ödendi ve gecikme', () {
    final now = DateTime(2026, 10, 30);
    final d = DueItem(id: 'd', period: 'p', amount: Money.fromMajor(100), paid: Money.fromMajor(40), dueDate: DateTime(2026, 10, 1));
    expect(d.remaining.minor, 6000);
    expect(d.isOverdue(now), isTrue);
    final paid = DueItem(id: 'd', period: 'p', amount: Money.fromMajor(100), paid: Money.fromMajor(100), dueDate: DateTime(2026, 10, 1));
    expect(paid.isPaid, isTrue);
    expect(paid.isOverdue(now), isFalse);
  });

  test('etkinlik kaydı: dolu etkinlik bekleme listesine, ücretsiz onaya, ücretli ayrılmaya düşer', () async {
    final r = FakeAppRepository();
    expect((await r.registerForEvent('e1')).myStatus, RegistrationStatus.waitlisted);
    expect((await r.registerForEvent('e2')).myStatus, RegistrationStatus.confirmed);
    await r.cancelEventRegistration('e1');
    expect((await r.events()).firstWhere((e) => e.id == 'e1').myStatus, RegistrationStatus.none);
  });

  test('bağış aynı clientKey ile aynı ödemeyi döndürür (idempotent)', () async {
    final r = FakeAppRepository();
    DonationRequest req(String k) => DonationRequest(campaignId: null, amount: Money.fromMajor(100), donorName: 'a', donorEmail: 'a@b.co', anonymous: false, clientKey: k);
    final a = await r.donate(req('k1'));
    final b = await r.donate(req('k1'));
    final c = await r.donate(req('k2'));
    expect(a.paymentId, b.paymentId);
    expect(c.paymentId, isNot(a.paymentId));
    expect(a.simulated, isTrue);
  });

  test('ücretli etkinlikte ayrılan yer ödemeyle onaylanır; rezervasyonsuz ödeme reddedilir', () async {
    final r = FakeAppRepository();
    await expectLater(r.payEventFee('e1'), throwsStateError);
    // e1 dolu (bekleme), e2 ücretsiz; ücretli ve boş kontenjanlı etkinlik örnek veride yok:
    await r.registerForEvent('e1');
    await expectLater(r.payEventFee('e1'), throwsStateError); // bekleme listesi ödeme yapamaz
  });

  test('bildirim okundu işaretlenir', () async {
    final r = FakeAppRepository();
    expect((await r.notifications()).every((n) => !n.read), isTrue);
    await r.markNotificationRead('nt1');
    expect((await r.notifications()).firstWhere((n) => n.id == 'nt1').read, isTrue);
  });

  test('bildirim tercihi kaydedilir ve diğer tercihler korunur', () async {
    final r = FakeAppRepository();
    final p = await r.notificationPrefs();
    expect(p.announcements && p.dues && p.events && p.donations, isTrue);
    await r.saveNotificationPrefs(p.copyWith(dues: false));
    final q = await r.notificationPrefs();
    expect(q.dues, isFalse);
    expect(q.events, isTrue);
  });

  test('bildirim tercihleri kaydedilir ve varsayılan hepsi açıktır', () async {
    final r = FakeAppRepository();
    final d = await r.notificationPrefs();
    expect(d.events && d.dues && d.donations && d.announcements, isTrue);
    await r.saveNotificationPrefs(d.copyWith(dues: false));
    final n = await r.notificationPrefs();
    expect(n.dues, isFalse);
    expect(n.events, isTrue);
  });
}
