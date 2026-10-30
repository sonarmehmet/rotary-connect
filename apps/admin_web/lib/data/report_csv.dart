import '../core/csv.dart';
import '../core/format.dart';
import 'models.dart';

String _iso(DateTime value) => value.toUtc().toIso8601String();

String _yesNo(bool value) => value ? 'evet' : 'hayir';

/// Ödemeler CSV'si. Tutar hem kuruş (kayıpsız) hem biçimli olarak yazılır.
/// Kişisel veri (ad, e-posta) içermez.
String paymentsCsv(List<PaymentRecord> rows) {
  return buildCsv(
    const [
      'odeme_id',
      'tur',
      'bagli_kayit',
      'tutar_kurus',
      'tutar',
      'para_birimi',
      'durum',
      'saglayici',
      'manuel',
      'simulasyon',
      'iade_kurus',
      'olusturma',
      'basari_zamani',
    ],
    [
      for (final p in rows)
        [
          p.id,
          p.kind.wireName,
          p.refId,
          '${p.amountMinor}',
          moneyText(p.amountMinor, currency: p.currency),
          p.currency,
          p.status.wireName,
          p.provider,
          _yesNo(p.manual),
          _yesNo(p.simulated),
          '${p.refundedMinor}',
          _iso(p.createdAt),
          p.succeededAt == null ? '' : _iso(p.succeededAt!),
        ],
    ],
  );
}

/// Aidat borçları CSV'si (üye adı yerine üye kimliği).
String duesCsv(List<MembershipDue> rows) {
  return buildCsv(
    const [
      'borc_id',
      'uye_id',
      'donem',
      'tutar_kurus',
      'odenen_kurus',
      'kalan_kurus',
      'para_birimi',
      'vade',
      'durum',
      'kismi_odeme',
    ],
    [
      for (final d in rows)
        [
          d.id,
          d.memberId,
          d.periodLabel,
          '${d.amountMinor}',
          '${d.paidMinor}',
          '${d.remainingMinor}',
          d.currency,
          _iso(d.dueDate),
          d.status.wireName,
          _yesNo(d.allowPartial),
        ],
    ],
  );
}

/// İadeler CSV'si.
String refundsCsv(List<RefundRecord> rows) {
  return buildCsv(
    const [
      'iade_id',
      'odeme_id',
      'tur',
      'tutar_kurus',
      'tutar',
      'para_birimi',
      'durum',
      'gerekce',
      'olusturma',
    ],
    [
      for (final r in rows)
        [
          r.id,
          r.paymentId,
          r.kind.wireName,
          '${r.amountMinor}',
          moneyText(r.amountMinor, currency: r.currency),
          r.currency,
          r.status.wireName,
          r.reason,
          _iso(r.createdAt),
        ],
    ],
  );
}
