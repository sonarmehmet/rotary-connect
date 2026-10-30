import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rotary_shared/shared.dart';

import '../../core/format.dart';
import '../../core/labels.dart';
import '../../data/donation_record.dart';
import '../../data/providers.dart';
import '../../ui/admin_table.dart';
import '../../ui/detail_dialog.dart';
import '../../ui/page_frame.dart';
import '../../ui/status_chip.dart';

/// Bağış kayıtları (salt okunur). Anonim bağışçının ad ve e-postası gösterilmez,
/// diğer e-postalar maskelenir. Simülasyon bağışları kampanya toplamına girmez ve işaretlenir.
class DonationsPage extends ConsumerWidget {
  const DonationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(donationsProvider);
    return AdminPageFrame(
      title: 'Bağış Kayıtları',
      subtitle: 'Yalnızca başarılı ve simülasyon olmayan bağışlar kampanya '
          'toplamına sayılır.',
      child: AsyncBody<List<DonationRecord>>(
        value: async,
        onRetry: () => ref.invalidate(donationsProvider),
        builder: (rows) => AdminTable<DonationRecord>(
          rows: rows,
          emptyMessage: 'Henüz bağış kaydı yok.',
          searchText: (d) =>
              '${d.id} ${d.paymentId} ${d.displayName} ${d.campaignId ?? 'genel'} '
              '${d.status.labelTr}',
          dateOf: (d) => d.createdAt,
          dateLabel: 'Bağış tarihi',
          initialSortColumn: 0,
          initialAscending: false,
          onRowTap: (d) => _detail(context, d),
          filters: [
            TableFilter<DonationRecord>(
              label: 'Durum',
              options: [
                for (final s in PaymentStatus.values)
                  FilterOption<DonationRecord>(s.labelTr, (d) => d.status == s),
              ],
            ),
            TableFilter<DonationRecord>(
              label: 'Bağışçı',
              options: [
                FilterOption<DonationRecord>('Üye/Kayıtlı', (d) => !d.isGuest),
                FilterOption<DonationRecord>('Misafir', (d) => d.isGuest),
                FilterOption<DonationRecord>('Anonim', (d) => d.anonymous),
              ],
            ),
            TableFilter<DonationRecord>(
              label: 'Kampanya',
              options: [
                FilterOption<DonationRecord>('Genel bağış', (d) => d.campaignId == null),
                FilterOption<DonationRecord>('Kampanyalı', (d) => d.campaignId != null),
              ],
            ),
          ],
          columns: [
            AdminColumn<DonationRecord>(
              label: 'Tarih',
              text: (d) => formatDateTime(d.createdAt),
              compare: (a, b) => a.createdAt.compareTo(b.createdAt),
            ),
            AdminColumn<DonationRecord>(label: 'Bağışçı', text: (d) => d.displayName),
            AdminColumn<DonationRecord>(
              label: 'Kampanya',
              text: (d) => d.campaignId ?? 'Genel bağış',
            ),
            AdminColumn<DonationRecord>(
              label: 'Tutar',
              numeric: true,
              text: (d) => moneyText(d.amountMinor, currency: d.currency),
              compare: (a, b) => a.amountMinor.compareTo(b.amountMinor),
            ),
            AdminColumn<DonationRecord>(
              label: 'Durum',
              text: (d) => d.status.labelTr,
              cell: (_, d) => StatusChip(label: d.status.labelTr, tone: d.status.tone),
            ),
            AdminColumn<DonationRecord>(
              label: 'Toplama dahil',
              text: (d) => d.simulated
                  ? 'Hayır (simülasyon)'
                  : (d.countsTowardTotal ? 'Evet' : 'Hayır'),
            ),
          ],
        ),
      ),
    );
  }

  void _detail(BuildContext context, DonationRecord d) {
    showDetailDialog(
      context,
      title: 'Bağış ${d.id}',
      rows: [
        ('Bağışçı', d.displayName),
        ('E-posta', d.displayEmail),
        ('Hesap', d.isGuest ? 'Misafir' : 'Kayıtlı kullanıcı'),
        ('Kampanya', d.campaignId ?? 'Genel bağış'),
        ('Tutar', moneyText(d.amountMinor, currency: d.currency)),
        ('Durum', d.status.labelTr),
        ('Ödeme no', d.paymentId),
        ('Makbuz no', d.receiptNo ?? '—'),
        ('Simülasyon', d.simulated ? 'Evet (kampanya toplamına girmez)' : 'Hayır'),
        ('Tarih', formatDateTime(d.createdAt)),
      ],
    );
  }
}
