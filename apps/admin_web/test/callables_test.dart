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
