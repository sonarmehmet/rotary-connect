import 'package:rotary_shared/shared.dart';
import 'package:test/test.dart';

void main() {
  group('PaymentStatus', () {
    test('geçerli geçişler', () {
      expect(PaymentStatus.created.canTransitionTo(PaymentStatus.pending), isTrue);
      expect(PaymentStatus.pending.canTransitionTo(PaymentStatus.succeeded), isTrue);
      expect(PaymentStatus.succeeded.canTransitionTo(PaymentStatus.refunded), isTrue);
    });

    test('geçersiz geçişler reddedilir', () {
      expect(PaymentStatus.created.canTransitionTo(PaymentStatus.succeeded), isFalse);
      expect(PaymentStatus.failed.canTransitionTo(PaymentStatus.succeeded), isFalse);
      expect(PaymentStatus.refunded.canTransitionTo(PaymentStatus.succeeded), isFalse);
    });

    test('yalnızca doğrulanmış ödemeler tahsilat sayılır', () {
      expect(PaymentStatus.pending.countsAsCollected, isFalse);
      expect(PaymentStatus.succeeded.countsAsCollected, isTrue);
      expect(PaymentStatus.refunded.countsAsCollected, isFalse);
    });

    test('tryParse bilinmeyen değerde null döner', () {
      expect(PaymentStatus.tryParse('partially_refunded'),
          PaymentStatus.partiallyRefunded);
      expect(PaymentStatus.tryParse('nope'), isNull);
    });
  });

  group('AppRole izinleri', () {
    test('ziyaretçi aidat göremez ama bağış yapabilir', () {
      expect(AppRole.visitor.can(Permission.viewOwnDues), isFalse);
      expect(AppRole.visitor.can(Permission.donate), isTrue);
    });

    test('içerik yöneticisi finansal işlem yapamaz', () {
      const role = AppRole.contentManager;
      expect(role.can(Permission.manageContent), isTrue);
      expect(role.can(Permission.issueRefund), isFalse);
      expect(role.can(Permission.exportFinancialData), isFalse);
    });

    test('finans yöneticisi iade ve dışa aktarma yapabilir, rol atayamaz', () {
      const role = AppRole.financeManager;
      expect(role.can(Permission.issueRefund), isTrue);
      expect(role.can(Permission.exportFinancialData), isTrue);
      expect(role.can(Permission.manageRoles), isFalse);
    });

    test('yalnızca sistem yöneticisi rol atayabilir', () {
      for (final r in AppRole.values) {
        expect(r.can(Permission.manageRoles), r == AppRole.systemAdmin);
      }
    });

    test('bilinmeyen rol ziyaretçiye düşer', () {
      expect(AppRole.fromWire('hacker'), AppRole.visitor);
      expect(AppRole.fromWire('club_member'), AppRole.clubMember);
    });
  });
}
