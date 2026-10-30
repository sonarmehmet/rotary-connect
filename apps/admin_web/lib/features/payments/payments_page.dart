import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rotary_shared/shared.dart';

import '../../core/format.dart';
import '../../core/labels.dart';
import '../../core/role_provider.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../ui/admin_table.dart';
import '../../ui/detail_dialog.dart';
import '../../ui/page_frame.dart';
import '../../ui/status_chip.dart';
import '../refunds/refund_dialog.dart';

/// Ödeme işlemleri (salt okunur liste; yazma yalnızca Functions).
/// Aidat, bağış ve etkinlik ücreti ayrı türlerdir; filtreyle ayrılır.
class PaymentsPage extends ConsumerWidget {
  const PaymentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canRefund = ref.watch(adminRoleProvider).can(Permission.issueRefund);
    final async = ref.watch(paymentsProvider);
    return AdminPageFrame(
      title: 'Ödeme İşlemleri',
      subtitle: 'Yalnızca başarılı ve (kısmen) iade edilmiş ödemeler '
          'tahsilat sayılır.',
      child: AsyncBody<List<PaymentRecord>>(
        value: async,
        onRetry: () => ref.invalidate(paymentsProvider),
        builder: (rows) => AdminTable<PaymentRecord>(
          rows: rows,
          emptyMessage: 'Henüz ödeme işlemi yok.',
          searchText: (p) =>
              '${p.id} ${p.refId} ${p.kind.labelTr} ${p.status.labelTr} ${p.provider}',
          dateOf: (p) => p.createdAt,
          dateLabel: 'İşlem tarihi',
          initialSortColumn: 0,
          initialAscending: false,
          onRowTap: (p) => _detail(context, p, canRefund),
          filters: [
            TableFilter<PaymentRecord>(
              label: 'Tür',
              options: [
                for (final k in PaymentKind.values)
                  FilterOption<PaymentRecord>(k.labelTr, (p) => p.kind == k),
              ],
            ),
            TableFilter<PaymentRecord>(
              label: 'Durum',
              options: [
                for (final s in PaymentStatus.values)
                  FilterOption<PaymentRecord>(s.labelTr, (p) => p.status == s),
              ],
            ),
            TableFilter<PaymentRecord>(
              label: 'Kaynak',
              options: [
                FilterOption<PaymentRecord>('Manuel', (p) => p.manual),
                FilterOption<PaymentRecord>('Çevrimiçi', (p) => !p.manual),
              ],
            ),
          ],
          columns: [
            AdminColumn<PaymentRecord>(
              label: 'Tarih',
              text: (p) => formatDateTime(p.createdAt),
              compare: (a, b) => a.createdAt.compareTo(b.createdAt),
            ),
            AdminColumn<PaymentRecord>(label: 'Kayıt no', text: (p) => p.id),
            AdminColumn<PaymentRecord>(label: 'Tür', text: (p) => p.kind.labelTr),
            AdminColumn<PaymentRecord>(
              label: 'Tutar',
              numeric: true,
              text: (p) => moneyText(p.amountMinor, currency: p.currency),
              compare: (a, b) => a.amountMinor.compareTo(b.amountMinor),
            ),
            AdminColumn<PaymentRecord>(
              label: 'İade edilen',
              numeric: true,
              text: (p) => moneyText(p.refundedMinor, currency: p.currency),
              compare: (a, b) => a.refundedMinor.compareTo(b.refundedMinor),
            ),
            AdminColumn<PaymentRecord>(
              label: 'Durum',
              text: (p) => p.status.labelTr,
              cell: (_, p) =>
                  StatusChip(label: p.status.labelTr, tone: p.status.tone),
            ),
            AdminColumn<PaymentRecord>(
              label: 'Kaynak',
              text: (p) => '${p.manual ? 'Manuel' : 'Çevrimiçi'}'
                  '${p.simulated ? ' (simülasyon)' : ''}',
            ),
          ],
        ),
      ),
    );
  }

  void _detail(BuildContext context, PaymentRecord p, bool canRefund) {
    showDetailDialog(
      context,
      title: 'Ödeme ${p.id}',
      rows: [
        ('Tür', p.kind.labelTr),
        ('Bağlı kayıt', p.refId),
        ('Durum', p.status.labelTr),
        ('Tutar', moneyText(p.amountMinor, currency: p.currency)),
        ('İade edilen', moneyText(p.refundedMinor, currency: p.currency)),
        ('İade edilebilir', moneyText(p.refundableMinor, currency: p.currency)),
        ('Sağlayıcı', '${p.provider}${p.simulated ? ' (simülasyon)' : ''}'),
        ('Manuel kayıt', p.manual ? 'Evet' : 'Hayır'),
        if (p.note != null) ('Not', p.note!),
        if (p.failureCode != null) ('Hata kodu', p.failureCode!),
        ('Oluşturma', formatDateTime(p.createdAt)),
        ('Başarı zamanı', formatDateTime(p.succeededAt)),
      ],
      actionsBuilder: (dialogContext) => [
        if (canRefund && p.isRefundable)
          FilledButton.icon(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              showDialog<bool>(
                context: context,
                builder: (_) => RefundDialog(payment: p),
              );
            },
            icon: const Icon(Icons.undo_outlined),
            label: const Text('İade başlat'),
          ),
      ],
    );
  }
}
