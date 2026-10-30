import 'package:rotary_shared/shared.dart';

import '../../data/models.dart';

/// Bir ödeme türünün toplamı. Türler asla birbirine karıştırılmaz.
class KindTotals {
  const KindTotals({
    required this.kind,
    required this.collectedMinor,
    required this.refundedMinor,
    required this.count,
  });

  final PaymentKind kind;

  /// Brüt tahsilat (sonradan iade edilenler dahil).
  final int collectedMinor;
  final int refundedMinor;
  final int count;

  /// Net = brüt − iade ("iade düşülmüş" toplam).
  int get netMinor => collectedMinor - refundedMinor;
}

/// Aggregate satırlarından tür bazlı toplamlar (yalnızca `currency`).
/// Her tür her zaman döner (veri yoksa sıfır).
List<KindTotals> totalsByKind(
  List<ReportAggregate> aggregates, {
  String currency = 'TRY',
  String? period,
}) {
  return [
    for (final kind in PaymentKind.values)
      () {
        var collected = 0;
        var refunded = 0;
        var count = 0;
        for (final a in aggregates) {
          if (a.kind != kind || a.currency != currency) continue;
          if (period != null && a.period != period) continue;
          collected += a.collectedMinor;
          refunded += a.refundedMinor;
          count += a.count;
        }
        return KindTotals(
          kind: kind,
          collectedMinor: collected,
          refundedMinor: refunded,
          count: count,
        );
      }(),
  ];
}
