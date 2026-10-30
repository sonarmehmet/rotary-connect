import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/labels.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../ui/admin_table.dart';
import '../../ui/detail_dialog.dart';
import '../../ui/page_frame.dart';
import '../../ui/status_chip.dart';

/// İade kayıtları (salt okunur). İade başlatma, Ödeme İşlemleri'ndeki ödeme
/// ayrıntısından yapılır; böylece iade her zaman bir ödemeye bağlı kalır.
class RefundsPage extends ConsumerWidget {
  const RefundsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(refundsProvider);
    return AdminPageFrame(
      title: 'İadeler',
      subtitle: 'İade başlatmak için Ödeme İşlemleri\'nden ilgili ödemeyi açın.',
      child: AsyncBody<List<RefundRecord>>(
        value: async,
        onRetry: () => ref.invalidate(refundsProvider),
        builder: (rows) => AdminTable<RefundRecord>(
          rows: rows,
          emptyMessage: 'Henüz iade kaydı yok.',
          searchText: (r) =>
              '${r.id} ${r.paymentId} ${r.kind.labelTr} ${r.reason} ${r.status.label}',
          dateOf: (r) => r.createdAt,
          dateLabel: 'İade tarihi',
          initialSortColumn: 0,
          initialAscending: false,
          onRowTap: (r) => showDetailDialog(
            context,
            title: 'İade ${r.id}',
            rows: [
              ('Ödeme', r.paymentId),
              ('Tür', r.kind.labelTr),
              ('Tutar', moneyText(r.amountMinor, currency: r.currency)),
              ('Durum', r.status.label),
              ('Gerekçe', r.reason),
              ('Tarih', formatDateTime(r.createdAt)),
            ],
          ),
          filters: [
            TableFilter<RefundRecord>(
              label: 'Durum',
              options: [
                for (final s in RefundStatus.values)
                  FilterOption<RefundRecord>(s.label, (r) => r.status == s),
              ],
            ),
          ],
          columns: [
            AdminColumn<RefundRecord>(
              label: 'Tarih',
              text: (r) => formatDateTime(r.createdAt),
              compare: (a, b) => a.createdAt.compareTo(b.createdAt),
            ),
            AdminColumn<RefundRecord>(label: 'İade no', text: (r) => r.id),
            AdminColumn<RefundRecord>(label: 'Ödeme', text: (r) => r.paymentId),
            AdminColumn<RefundRecord>(label: 'Tür', text: (r) => r.kind.labelTr),
            AdminColumn<RefundRecord>(
              label: 'Tutar',
              numeric: true,
              text: (r) => moneyText(r.amountMinor, currency: r.currency),
              compare: (a, b) => a.amountMinor.compareTo(b.amountMinor),
            ),
            AdminColumn<RefundRecord>(
              label: 'Durum',
              text: (r) => r.status.label,
              cell: (_, r) => StatusChip(label: r.status.label, tone: r.status.tone),
            ),
            AdminColumn<RefundRecord>(label: 'Gerekçe', text: (r) => r.reason),
          ],
        ),
      ),
    );
  }
}
