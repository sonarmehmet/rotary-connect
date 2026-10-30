import 'package:rotary_shared/shared.dart';

/// donations/{id}. Yazma: yalnızca Functions. Durum, bağlı ödemenin durumunu izler.
/// Bağışçı kişisel verisi: anonim bağışta ad ve e-posta panelde GİZLENİR ([displayName]).
class DonationRecord {
  const DonationRecord({
    required this.id,
    required this.paymentId,
    required this.amountMinor,
    required this.status,
    required this.donorName,
    required this.anonymous,
    required this.createdAt,
    this.campaignId,
    this.userId,
    this.donorEmail,
    this.currency = 'TRY',
    this.receiptNo,
    this.simulated = false,
  });

  final String id;
  final String paymentId;
  final String? campaignId;
  final String? userId;
  final String donorName;
  final String? donorEmail;
  final bool anonymous;
  final int amountMinor;
  final String currency;
  final PaymentStatus status;
  final String? receiptNo;
  final bool simulated;
  final DateTime createdAt;

  bool get isGuest => userId == null;

  /// Kampanya toplamına yalnızca başarılı, simülasyon olmayan bağışlar girer.
  bool get countsTowardTotal =>
      !simulated &&
      (status == PaymentStatus.succeeded ||
          status == PaymentStatus.partiallyRefunded);

  String get displayName => anonymous ? 'Anonim bağışçı' : donorName;

  /// Anonim bağışta e-posta hiç gösterilmez; diğerlerinde maskelenir (a***@b.com).
  String get displayEmail {
    final e = donorEmail;
    if (anonymous || e == null || !e.contains('@')) return '—';
    final parts = e.split('@');
    final local = parts.first;
    final shown = local.isEmpty ? '' : local[0];
    return '$shown***@${parts.last}';
  }
}
