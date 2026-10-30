import 'package:flutter_test/flutter_test.dart';
import 'package:rotary_admin_web/core/admin_exception.dart';
import 'package:rotary_admin_web/core/format.dart';
import 'package:rotary_admin_web/data/models.dart';
import 'package:rotary_admin_web/data/remote/admin_callables.dart';
import 'package:rotary_admin_web/data/remote/callable_client.dart';
import 'package:rotary_shared/shared.dart';

class _RecordingClient implements CallableClient {
  _RecordingClient(this.response);

  final Map<String, Object?> response;
  String? name;
  Map<String, Object?>? data;

  @override
  Future<Map<String, Object?>> call(
    String name,
    Map<String, Object?> data,
  ) async {
    this.name = name;
    this.data = data;
    return response;
  }
}

void main() {
  test('sendAnnouncement: sunucu sözleşmesine uygun gövde ve cevap', () async {
    final client = _RecordingClient({
      'recipients': 10,
      'sent': 8,
      'skippedByPreferences': 2,
    });
    final result = await AdminCallables(client).sendAnnouncement(
      const AnnouncementRequest(
        audience: AnnouncementAudience.role,
        role: AppRole.clubMember,
        title: '  Başlık ',
        body: ' Metin ',
        route: AnnouncementRoute.events,
        clientKey: 'anahtar_001',
      ),
    );
    expect(client.name, 'sendAnnouncement');
    expect(client.data, {
      'audience': {'type': 'role', 'role': 'club_member'},
      'title': 'Başlık',
      'body': 'Metin',
      'route': '/events',
      'clientKey': 'anahtar_001',
    });
    expect(result.recipients, 10);
    expect(result.sent, 8);
    expect(result.skippedByPreferences, 2);
  });

  test('sendAnnouncement: "all" hedefinde rol alanı gönderilmez', () async {
    final client = _RecordingClient({
      'recipients': 1,
      'sent': 1,
      'skippedByPreferences': 0,
    });
    await AdminCallables(client).sendAnnouncement(
      const AnnouncementRequest(
        audience: AnnouncementAudience.all,
        role: AppRole.clubMember, // yok sayılmalı
        title: 'T',
        body: 'B',
        route: AnnouncementRoute.news,
        clientKey: 'anahtar_002',
      ),
    );
    expect(client.data!['audience'], {'type': 'all'});
  });

  test('recordManualPayment: tutar kuruş tamsayı, tarih ms, userId isteğe bağlı',
      () async {
    final client = _RecordingClient({'paymentId': 'pay_x'});
    final id = await AdminCallables(client).recordManualPayment(
      ManualPaymentRequest(
        kind: PaymentKind.membershipDue,
        refId: 'due_1',
        amountMinor: 120000,
        note: ' dekont 123 ',
        receivedAt: DateTime.utc(2026, 10, 28, 9),
        userId: 'usr_1',
      ),
    );
    expect(id, 'pay_x');
    expect(client.name, 'recordManualPayment');
    expect(client.data, {
      'kind': 'membership_due',
      'refId': 'due_1',
      'userId': 'usr_1',
      'amountMinor': 120000,
      'receivedAtMs': DateTime.utc(2026, 10, 28, 9).millisecondsSinceEpoch,
      'note': 'dekont 123',
    });
    expect(client.data!['amountMinor'], isA<int>());
  });

  test('userId yoksa gövdede hiç yer almaz', () async {
    final client = _RecordingClient({'paymentId': 'pay_y'});
    await AdminCallables(client).recordManualPayment(
      ManualPaymentRequest(
        kind: PaymentKind.donation,
        refId: 'general',
        amountMinor: 100,
        note: 'elden bağış',
        receivedAt: istanbulToInstant(2026, 10, 1),
      ),
    );
    expect(client.data!.containsKey('userId'), isFalse);
  });

  test('bozuk sunucu cevabı açık hata verir', () async {
    final bad = _RecordingClient({'recipients': '10'});
    await expectLater(
      AdminCallables(bad).sendAnnouncement(
        const AnnouncementRequest(
          audience: AnnouncementAudience.all,
          title: 'T',
          body: 'B',
          route: AnnouncementRoute.news,
          clientKey: 'anahtar_003',
        ),
      ),
      throwsStateError,
    );
    final noId = _RecordingClient({});
    await expectLater(
      AdminCallables(noId).recordManualPayment(
        ManualPaymentRequest(
          kind: PaymentKind.donation,
          refId: 'general',
          amountMinor: 100,
          note: 'elden bağış',
          receivedAt: istanbulToInstant(2026, 10, 1),
        ),
      ),
      throwsStateError,
    );
  });

  test('yönetim callable gövdeleri sunucu sözleşmesiyle birebir', () async {
    final client = _RecordingClient({
      'created': 3,
      'skipped': 1,
      'refundId': 'ref_1',
      'csv': 'x',
    });
    final calls = AdminCallables(client);

    await calls.assignRole('usr_1', AppRole.financeManager);
    expect(client.name, 'assignRole');
    expect(client.data, {'userId': 'usr_1', 'role': 'finance_manager'});

    await calls.cancelDue('due_1', '  Yanlış atama ');
    expect(client.name, 'cancelDue');
    expect(client.data, {'dueId': 'due_1', 'reason': 'Yanlış atama'});

    await calls.approveMembership('mem_7', ' ÜY-0007 ');
    expect(client.name, 'approveMembership');
    expect(client.data, {'memberId': 'mem_7', 'memberNo': 'ÜY-0007'});

    await calls.endMembership('mem_1', MemberStatus.resigned);
    expect(client.name, 'endMembership');
    expect(client.data, {'memberId': 'mem_1', 'to': 'resigned'});

    final due = DateTime.utc(2027, 11, 30);
    final out = await calls.assignDues(
      NewDuesRequest(
        periodLabel: ' 2027-2028 ',
        amountMinor: 150000,
        dueDate: due,
        allowPartial: true,
      ),
    );
    expect(out.created, 3);
    expect(out.skipped, 1);
    expect(client.name, 'assignDues');
    expect(client.data, {
      'periodLabel': '2027-2028',
      'amountMinor': 150000,
      'dueDateMs': due.millisecondsSinceEpoch,
      'allowPartial': true,
    });

    final id = await calls.issueRefund(
      const RefundRequest(paymentId: 'pay_1', amountMinor: 500, reason: ' Mükerrer '),
    );
    expect(id, 'ref_1');
    expect(client.data, {'paymentId': 'pay_1', 'amountMinor': 500, 'reason': 'Mükerrer'});
  });

  test('exportReport: İstanbul gün sınırları ms olarak, aralıksızsa alan yok', () async {
    final client = _RecordingClient({'csv': '\uFEFFa;b\r\n'});
    final calls = AdminCallables(client);

    await calls.exportReport(const ExportRequest(kind: ExportKind.payments));
    expect(client.data, {'kind': 'payments'});

    await calls.exportReport(
      ExportRequest(
        kind: ExportKind.dues,
        range: DateRange(DateTime(2026, 10, 1), DateTime(2026, 10, 31)),
      ),
    );
    expect(client.data!['kind'], 'dues');
    expect(
      client.data!['fromMs'],
      istanbulToInstant(2026, 10, 1).millisecondsSinceEpoch,
    );
    // Bitiş: 31 Ekim 23:59:59.999 İstanbul = 1 Kasım 00:00 İstanbul − 1 ms.
    expect(
      client.data!['toMs'],
      istanbulToInstant(2026, 11, 1).millisecondsSinceEpoch - 1,
    );
  });

  test('ay sonu aralığı bir sonraki aya taşar (31 Aralık)', () async {
    final client = _RecordingClient({'csv': 'x'});
    await AdminCallables(client).exportReport(
      ExportRequest(
        kind: ExportKind.refunds,
        range: DateRange(DateTime(2026, 12, 1), DateTime(2026, 12, 31)),
      ),
    );
    expect(
      client.data!['toMs'],
      istanbulToInstant(2027, 1, 1).millisecondsSinceEpoch - 1,
    );
  });

  group('callableErrorToException', () {
    test('reason details içinden taşınır', () {
      final e = callableErrorToException(
        'failed-precondition',
        'dolu',
        {'reason': 'sold_out'},
      );
      expect(e.code, 'failed-precondition');
      expect(e.reason, 'sold_out');
      expect(errorMessageTr(e), 'Etkinlik kontenjanı dolu.');
    });

    test('bilinmeyen kod internal olur ve ham mesaj sızmaz', () {
      final e = callableErrorToException(
        'weird',
        'SELECT * FROM secrets',
        null,
      );
      expect(e.code, 'internal');
      expect(e.message, isNull);
      expect(errorMessageTr(e), isNot(contains('SELECT')));
    });

    test('details Map değilse reason yok sayılır', () {
      expect(callableErrorToException('not-found', 'x', 'metin').reason, isNull);
      expect(callableErrorToException('not-found', 'x', {'reason': 5}).reason, isNull);
    });
  });
}
