import 'package:rotary_shared/shared.dart';

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

  static int _int(Map<String, Object?> m, String key) {
    final v = m[key];
    if (v is int) return v;
    if (v is num && v == v.roundToDouble()) return v.toInt();
    throw StateError('Sunucu cevabında "$key" tamsayı değil');
  }
}
