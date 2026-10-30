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

/// Etkinlik katılımcı kayıtları (salt okunur; yazma yalnızca Functions).
class RegistrationsPage extends ConsumerWidget {
  const RegistrationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(registrationsProvider);
    return AdminPageFrame(
      title: 'Katılımcı Kayıtları',
      subtitle: 'Kontenjan ve durum değişiklikleri yalnızca sunucuda yapılır.',
      child: AsyncBody<List<EventRegistration>>(
        value: async,
        onRetry: () => ref.invalidate(registrationsProvider),
        builder: (rows) => AdminTable<EventRegistration>(
          rows: rows,
          emptyMessage: 'Henüz katılımcı kaydı yok.',
          searchText: (r) =>
              '${r.participantName} ${r.eventTitle} ${r.status.label}',
          dateOf: (r) => r.createdAt,
          dateLabel: 'Kayıt tarihi',
          initialSortColumn: 3,
          initialAscending: false,
          onRowTap: (r) => showDetailDialog(
            context,
            title: r.participantName,
            rows: [
              ('Etkinlik', r.eventTitle),
              ('Durum', r.status.label),
              ('Kayıt', formatDateTime(r.createdAt)),
              if (r.reservedUntil != null)
                ('Rezervasyon sonu', formatDateTime(r.reservedUntil)),
              if (r.waitlistPosition != null)
                ('Bekleme sırası', '${r.waitlistPosition}'),
              ('Ödeme', r.paymentId ?? '—'),
            ],
          ),
          filters: [
            TableFilter<EventRegistration>(
              label: 'Durum',
              options: [
                for (final s in RegistrationStatus.values)
                  FilterOption<EventRegistration>(s.label, (r) => r.status == s),
              ],
            ),
          ],
          columns: [
            AdminColumn<EventRegistration>(
              label: 'Katılımcı',
              text: (r) => r.participantName,
              compare: (a, b) => a.participantName.compareTo(b.participantName),
            ),
            AdminColumn<EventRegistration>(label: 'Etkinlik', text: (r) => r.eventTitle),
            AdminColumn<EventRegistration>(
              label: 'Durum',
              text: (r) => r.status.label,
              cell: (_, r) => StatusChip(label: r.status.label, tone: r.status.tone),
            ),
            AdminColumn<EventRegistration>(
              label: 'Kayıt',
              text: (r) => formatDateTime(r.createdAt),
              compare: (a, b) => a.createdAt.compareTo(b.createdAt),
            ),
          ],
        ),
      ),
    );
  }
}
