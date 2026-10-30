import 'package:flutter_test/flutter_test.dart';
import 'package:rotary_admin_web/core/admin_exception.dart';
import 'package:rotary_admin_web/core/format.dart';
import 'package:rotary_admin_web/data/fake_admin_repository.dart';
import 'package:rotary_admin_web/data/models.dart';
import 'package:rotary_admin_web/data/sample_data.dart';
import 'package:rotary_admin_web/features/overview/overview_logic.dart';
import 'package:rotary_shared/shared.dart';

Matcher throwsCode(String code) => throwsA(
      isA<AdminException>().having((e) => e.code, 'code', code),
    );

void main() {
  group('örnek veri tutarlılığı', () {
    test('iade edilen tutar ödeme tutarını aşmaz, iadeler ödemelerle uyumlu', () {
      final data = SampleData.standard();
      for (final p in data.payments) {
        expect(p.refundedMinor <= p.amountMinor, isTrue, reason: p.id);
        if (p.status == PaymentStatus.refunded) {
          expect(p.refundedMinor, p.amountMinor);
        }
      }
    });

    test('aggregate yalnızca tahsil edilmiş ödemeleri sayar', () {
      final data = SampleData.standard();
      final aggregates = buildAggregates(data.payments);
      final collected = data.payments.where(
        (p) =>
            p.status == PaymentStatus.succeeded ||
            p.status == PaymentStatus.partiallyRefunded ||
            p.status == PaymentStatus.refunded,
      );
      expect(
        aggregates.fold<int>(0, (s, a) => s + a.count),
        collected.length,
      );
      expect(
        aggregates.fold<int>(0, (s, a) => s + a.collectedMinor),
        collected.fold<int>(0, (s, p) => s + p.amountMinor),
      );
    });

    test('tür toplamları ayrı ve net = brüt − iade', () {
      final aggregates = buildAggregates(SampleData.standard().payments);
      final totals = totalsByKind(aggregates);
      expect(totals.map((t) => t.kind), PaymentKind.values);
      for (final t in totals) {
        expect(t.netMinor, t.collectedMinor - t.refundedMinor);
      }
      final allRefunded = aggregates.fold<int>(0, (s, a) => s + a.refundedMinor);
      expect(totals.fold<int>(0, (s, t) => s + t.refundedMinor), allRefunded);
    });
  });

  group('FakeAdminRepository kuralları', () {
    late FakeAdminRepository repo;
    setUp(() => repo = FakeAdminRepository());

    test('iade üst sınırı: kalan tutarı aşan iade reddedilir', () async {
      final payments = await repo.listPayments();
      final p = payments.firstWhere((p) => p.status == PaymentStatus.pending);
      await expectLater(
        repo.issueRefund(
          RefundRequest(paymentId: p.id, amountMinor: 100, reason: 'deneme'),
        ),
        throwsCode('failed-precondition'),
      );
    });

    test('başarılı ödemeden kısmi sonra tam iade; durum makinesi izlenir', () async {
      final p = (await repo.listPayments()).firstWhere(
        (p) =>
            p.status == PaymentStatus.succeeded &&
            !(p.id == 'pay_001' || p.id == 'pay_002'), // bekleyen iadesi olanlar
      );
      await repo.issueRefund(
        RefundRequest(
          paymentId: p.id,
          amountMinor: p.amountMinor ~/ 2,
          reason: 'kısmi',
        ),
      );
      var after = (await repo.listPayments()).firstWhere((x) => x.id == p.id);
      expect(after.status, PaymentStatus.partiallyRefunded);

      await repo.issueRefund(
        RefundRequest(
          paymentId: p.id,
          amountMinor: p.amountMinor - p.amountMinor ~/ 2,
          reason: 'kalan',
        ),
      );
      after = (await repo.listPayments()).firstWhere((x) => x.id == p.id);
      expect(after.status, PaymentStatus.refunded);
      expect(after.refundedMinor, p.amountMinor);

      await expectLater(
        repo.issueRefund(
          RefundRequest(paymentId: p.id, amountMinor: 1, reason: 'fazla'),
        ),
        throwsCode('failed-precondition'),
      );
    });

    test('iade denetim kaydı üretir', () async {
      final before = (await repo.listAuditLogs()).length;
      final p = (await repo.listPayments()).firstWhere(
        (p) => p.status == PaymentStatus.succeeded && p.id != 'pay_001',
      );
      await repo.issueRefund(
        RefundRequest(paymentId: p.id, amountMinor: 100, reason: 'denetim'),
      );
      final logs = await repo.listAuditLogs();
      expect(logs.length, before + 1);
      expect(logs.first.action, 'refund.issue');
    });

    test('manuel ödeme mükerrer anahtarla ikinci kez kaydedilmez', () async {
      final due = (await repo.listDues()).firstWhere(
        (d) => d.status == DueStatus.unpaid && d.allowPartial,
      );
      final request = ManualPaymentRequest(
        kind: PaymentKind.membershipDue,
        refId: due.id,
        amountMinor: 10000,
        note: 'havale',
        idempotencyKey: 'k1',
      );
      await repo.recordManualPayment(request);
      await expectLater(
        repo.recordManualPayment(request),
        throwsCode('already-exists'),
      );
      final updated =
          (await repo.listDues()).firstWhere((d) => d.id == due.id);
      expect(updated.paidMinor, 10000);
      expect(updated.status, DueStatus.partiallyPaid);
    });

    test('kısmi ödeme kapalıysa kalandan az ödeme reddedilir', () async {
      final due = (await repo.listDues()).firstWhere(
        (d) => d.status == DueStatus.overdue && !d.allowPartial,
      );
      await expectLater(
        repo.recordManualPayment(
          ManualPaymentRequest(
            kind: PaymentKind.membershipDue,
            refId: due.id,
            amountMinor: 100,
            note: 'eksik',
            idempotencyKey: 'k2',
          ),
        ),
        throwsCode('failed-precondition'),
      );
      await repo.recordManualPayment(
        ManualPaymentRequest(
          kind: PaymentKind.membershipDue,
          refId: due.id,
          amountMinor: due.remainingMinor,
          note: 'tam',
          idempotencyKey: 'k3',
        ),
      );
      final updated =
          (await repo.listDues()).firstWhere((d) => d.id == due.id);
      expect(updated.status, DueStatus.paid);
    });

    test('kalan borcu aşan ödeme reddedilir', () async {
      final due = (await repo.listDues()).firstWhere(
        (d) => d.status == DueStatus.unpaid,
      );
      await expectLater(
        repo.recordManualPayment(
          ManualPaymentRequest(
            kind: PaymentKind.membershipDue,
            refId: due.id,
            amountMinor: due.remainingMinor + 1,
            note: 'fazla',
            idempotencyKey: 'k4',
          ),
        ),
        throwsCode('failed-precondition'),
      );
    });

    test('aynı dönem için borç tekrar atanamaz', () async {
      final request = NewDuesRequest(
        periodLabel: '2027-2028',
        amountMinor: 150000,
        dueDate: istanbulToInstant(2027, 11, 30),
        allowPartial: false,
      );
      await repo.createDues(request);
      await expectLater(repo.createDues(request), throwsCode('already-exists'));
      final dues = await repo.listDues();
      expect(dues.where((d) => d.periodLabel == '2027-2028').length, 6);
    });

    test('sıfır veya negatif tutar reddedilir', () async {
      await expectLater(
        repo.createDues(
          NewDuesRequest(
            periodLabel: 'x',
            amountMinor: 0,
            dueDate: istanbulToInstant(2027, 1, 1),
            allowPartial: false,
          ),
        ),
        throwsCode('invalid-argument'),
      );
    });

    test('kampanya kaydetme: boş id oluşturur, dolu id günceller', () async {
      final list = await repo.listCampaigns();
      final first = list.first;
      await repo.saveCampaign(
        Campaign(
          id: '',
          title: 'Yeni',
          description: 'Açıklama metni',
          category: CampaignCategory.general,
          goalMinor: 100000,
          status: CampaignStatus.draft,
          createdAt: SampleData.now,
        ),
      );
      expect((await repo.listCampaigns()).length, list.length + 1);
      expect((await repo.listCampaigns()).first.id, isNotEmpty);

      await repo.saveCampaign(
        Campaign(
          id: first.id,
          title: 'Güncel',
          description: first.description,
          category: first.category,
          goalMinor: first.goalMinor,
          status: first.status,
          createdAt: first.createdAt,
        ),
      );
      final updated =
          (await repo.listCampaigns()).firstWhere((c) => c.id == first.id);
      expect(updated.title, 'Güncel');
    });

    test('var olmayan kaydı güncelleme reddedilir', () async {
      await expectLater(
        repo.saveProject(
          Project(
            id: 'yok',
            title: 'x',
            description: 'y',
            leadName: 'z',
            status: ProjectStatus.draft,
            startDate: SampleData.now,
            goals: 'g',
          ),
        ),
        throwsCode('failed-precondition'),
      );
    });

    test('dışa aktarma: BOM, başlık, aralık süzmesi, denetim kaydı', () async {
      final all = await repo.exportReport(
        const ExportRequest(kind: ExportKind.payments),
      );
      expect(all.startsWith('﻿odeme_id;'), isTrue);
      final payments = await repo.listPayments();
      // başlık + satırlar (+ boş son parça)
      expect(all.split('\r\n').length, payments.length + 2);

      final none = await repo.exportReport(
        ExportRequest(
          kind: ExportKind.payments,
          range: DateRange(DateTime(2001, 1, 1), DateTime(2001, 1, 2)),
        ),
      );
      expect(none.split('\r\n').length, 2); // yalnızca başlık
      expect((await repo.listAuditLogs()).first.action, 'export.financial');
    });

    test('dışa aktarma kişisel veri içermez', () async {
      final csv = await repo.exportReport(
        const ExportRequest(kind: ExportKind.dues),
      );
      expect(csv.contains('Örnek Üye'), isFalse);
    });

    test('üyelik onayı: üye no zorunlu, yalnızca bekleyen, rol club_member olur',
        () async {
      await expectLater(
        repo.approveMembership('mem_7', '  '),
        throwsCode('invalid-argument'),
      );
      await expectLater(
        repo.approveMembership('mem_1', 'ÜY-9999'), // zaten aktif
        throwsCode('failed-precondition'),
      );
      await expectLater(
        repo.approveMembership('mem_7', 'ÜY-0001'), // numara kullanımda
        throwsCode('already-exists'),
      );
      await repo.approveMembership('mem_7', 'ÜY-0007');
      final m = (await repo.listClubMembers()).firstWhere((m) => m.id == 'mem_7');
      expect(m.status, MemberStatus.active);
      expect(m.memberNo, 'ÜY-0007');
      final u = (await repo.listUsers()).firstWhere((u) => u.id == 'usr_7');
      expect(u.role, AppRole.clubMember);
      expect((await repo.listAuditLogs()).first.action, 'club_member.approve');
    });

    test('üyelik sonlanınca rol düşer; yalnızca aktif üyelik sonlandırılır',
        () async {
      await repo.endMembership('mem_1', MemberStatus.suspended);
      final u = (await repo.listUsers()).firstWhere((u) => u.id == 'usr_1');
      expect(u.role, AppRole.registeredUser);
      await expectLater(
        repo.endMembership('mem_1', MemberStatus.resigned),
        throwsCode('failed-precondition'),
      );
      await expectLater(
        repo.endMembership('mem_2', MemberStatus.active),
        throwsCode('invalid-argument'),
      );
    });

    test('rol atama: denetim kaydı, aynı rol reddi, son yönetici korunur',
        () async {
      await repo.assignRole('usr_content_1', AppRole.financeManager);
      expect(
        (await repo.listUsers()).firstWhere((u) => u.id == 'usr_content_1').role,
        AppRole.financeManager,
      );
      expect((await repo.listAuditLogs()).first.action, 'role.assign');
      await expectLater(
        repo.assignRole('usr_content_1', AppRole.financeManager),
        throwsCode('failed-precondition'),
      );
      await expectLater(
        repo.assignRole('usr_admin_1', AppRole.registeredUser),
        throwsCode('failed-precondition'),
      );
    });
  });
}
