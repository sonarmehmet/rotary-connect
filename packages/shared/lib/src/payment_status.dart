/// Ödeme türü: aidat, bağış ve etkinlik ücreti birbirine karıştırılmaz.
enum PaymentKind {
  membershipDue('membership_due'),
  donation('donation'),
  eventFee('event_fee');

  const PaymentKind(this.wireName);
  final String wireName;
}

/// Ödeme durum makinesi. functions/src/payments/paymentState.ts ile BİREBİR aynı olmalıdır.
enum PaymentStatus {
  created('created'),
  pending('pending'),
  succeeded('succeeded'),
  failed('failed'),
  cancelled('cancelled'),
  refunded('refunded'),
  partiallyRefunded('partially_refunded');

  const PaymentStatus(this.wireName);
  final String wireName;

  static PaymentStatus? tryParse(String? value) {
    for (final s in PaymentStatus.values) {
      if (s.wireName == value) return s;
    }
    return null;
  }

  /// Bu durumdan geçilebilecek durumlar.
  Set<PaymentStatus> get allowedNext {
    switch (this) {
      case PaymentStatus.created:
        return {
          PaymentStatus.pending,
          PaymentStatus.failed,
          PaymentStatus.cancelled,
        };
      case PaymentStatus.pending:
        return {
          PaymentStatus.succeeded,
          PaymentStatus.failed,
          PaymentStatus.cancelled,
        };
      case PaymentStatus.succeeded:
        return {PaymentStatus.refunded, PaymentStatus.partiallyRefunded};
      case PaymentStatus.partiallyRefunded:
        return {PaymentStatus.refunded, PaymentStatus.partiallyRefunded};
      case PaymentStatus.failed:
      case PaymentStatus.cancelled:
      case PaymentStatus.refunded:
        return const {};
    }
  }

  bool canTransitionTo(PaymentStatus next) => allowedNext.contains(next);

  /// Yalnızca gerçekten tahsil edilmiş (doğrulanmış) ödemeler toplamlara girer.
  bool get countsAsCollected =>
      this == PaymentStatus.succeeded || this == PaymentStatus.partiallyRefunded;
}
