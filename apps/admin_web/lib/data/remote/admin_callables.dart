import 'package:rotary_shared/shared.dart';

import '../../core/format.dart';
import '../models.dart';
import 'callable_client.dart';

/// Sunucudaki callable'ların istek/cevap sözleşmesi (functions/src/handlers).
/// Yalnızca sunucuda GERÇEKTEN var olan callable'lar burada yer alır; yenisi
/// eklendikçe genişletilir.
class AdminCallables {
  const AdminCallables(this._client);

  final CallableClient _client;

  /// `sendAnnouncement` (içerik/sistem yöneticisi).
  Future<AnnouncementResult> sendAnnouncement(AnnouncementRequest r) async {
    final out = await _client.call('sendAnnouncement', {
      'audience': {
        'type': r.audience.wireName,
        if (r.audience == AnnouncementAudience.role && r.role != null)
          'role': r.role!.wireName,
      },
      'title': r.title.trim(),
      'body': r.body.trim(),
      'route': r.route.path,
      'clientKey': r.clientKey,
    });
    return AnnouncementResult(
      recipients: _int(out, 'recipients'),
      sent: _int(out, 'sent'),
      skippedByPreferences: _int(out, 'skippedByPreferences'),
    );
  }

  /// `recordManualPayment` (yalnızca finans yöneticisi). Cevap: `paymentId`.
  Future<String> recordManualPayment(ManualPaymentRequest r) async {
    final out = await _client.call('recordManualPayment', {
      'kind': r.kind.wireName,
      'refId': r.refId,
      if (r.userId != null) 'userId': r.userId,
      'amountMinor': r.amountMinor,
      'receivedAtMs': r.receivedAt.toUtc().millisecondsSinceEpoch,
      'note': r.note.trim(),
    });
    final id = out['paymentId'];
    if (id is! String || id.isEmpty) {
      throw StateError('recordManualPayment: paymentId eksik');
    }
    return id;
  }

  /// `cancelDue` (yalnızca finans yöneticisi). Ödemesi alınmış borç iptal edilemez.
  Future<void> cancelDue(String dueId, String reason) async {
    await _client.call('cancelDue', {'dueId': dueId, 'reason': reason.trim()});
  }

  /// `assignRole` (yalnızca sistem yöneticisi). `club_member` atanamaz.
  Future<void> assignRole(String userId, AppRole role) async {
    await _client.call('assignRole', {'userId': userId, 'role': role.wireName});
  }

  /// `approveMembership` (yalnızca sistem yöneticisi).
  Future<void> approveMembership(String memberId, String memberNo) async {
    await _client.call('approveMembership', {
      'memberId': memberId,
      'memberNo': memberNo.trim(),
    });
  }

  /// `endMembership` (yalnızca sistem yöneticisi): `suspended` | `resigned`.
  Future<void> endMembership(String memberId, MemberStatus to) async {
    await _client.call('endMembership', {'memberId': memberId, 'to': to.wireName});
  }

  /// `assignDues` (yalnızca finans yöneticisi).
  Future<({int created, int skipped})> assignDues(NewDuesRequest r) async {
    final out = await _client.call('assignDues', {
      'periodLabel': r.periodLabel.trim(),
      'amountMinor': r.amountMinor,
      'dueDateMs': r.dueDate.toUtc().millisecondsSinceEpoch,
      'allowPartial': r.allowPartial,
      if (r.memberId != null) 'memberId': r.memberId,
    });
    return (created: _int(out, 'created'), skipped: _int(out, 'skipped'));
  }

  /// `issueRefund` (yalnızca finans yöneticisi).
  Future<String> issueRefund(RefundRequest r) async {
    final out = await _client.call('issueRefund', {
      'paymentId': r.paymentId,
      'amountMinor': r.amountMinor,
      'reason': r.reason.trim(),
    });
    final id = out['refundId'];
    if (id is! String || id.isEmpty) {
      throw StateError('issueRefund: refundId eksik');
    }
    return id;
  }

  /// `exportReport` (yalnızca finans yöneticisi). Tarih aralığı İstanbul
  /// günlerine göre kapalıdır: başlangıç günü 00:00 → bitiş günü 23:59:59.999.
  Future<String> exportReport(ExportRequest r) async {
    final range = r.range;
    final out = await _client.call('exportReport', {
      'kind': r.kind.wireName,
      if (range != null)
        'fromMs': istanbulToInstant(
          range.start.year,
          range.start.month,
          range.start.day,
        ).millisecondsSinceEpoch,
      if (range != null)
        'toMs': istanbulToInstant(
              range.end.year,
              range.end.month,
              range.end.day + 1,
            ).millisecondsSinceEpoch -
            1,
    });
    final csv = out['csv'];
    if (csv is! String) throw StateError('exportReport: csv eksik');
    return csv;
  }

  static int _int(Map<String, Object?> m, String key) {
    final v = m[key];
    if (v is int) return v;
    if (v is num && v == v.roundToDouble()) return v.toInt();
    throw StateError('Sunucu cevabında "$key" tamsayı değil');
  }
}
