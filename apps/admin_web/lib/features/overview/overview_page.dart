import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rotary_shared/shared.dart';

import '../../core/format.dart';
import '../../core/labels.dart';
import '../../core/role_provider.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../ui/page_frame.dart';
import '../../ui/state_views.dart';
import 'overview_logic.dart';

/// Genel Bakış: bağış / aidat / etkinlik toplamları AYRI kartlardır;
/// gösterilen net tutar iade düşülmüştür.
class OverviewPage extends ConsumerWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(adminRoleProvider);
    if (!role.can(Permission.viewFinancialReports)) {
      return const NoAccessView();
    }
    final aggregates = ref.watch(aggregatesProvider);
    final campaigns = ref.watch(campaignsProvider);
    final events = ref.watch(eventsProvider);
    final dues = ref.watch(duesProvider);
    return AdminPageFrame(
      title: 'Genel Bakış',
      subtitle: 'Tutarlar tahsil edilmiş ödemelerden, iade düşülerek hesaplanır.',
      child: AsyncBody<List<ReportAggregate>>(
        value: aggregates,
        onRetry: () => ref.invalidate(aggregatesProvider),
        builder: (rows) {
          final totals = totalsByKind(rows);
          final month = periodOf(ref.read(adminClockProvider)());
          final monthTotals = totalsByKind(rows, period: month);
          final openDues = (dues.valueOrNull ?? const <MembershipDue>[])
              .where(
                (d) =>
                    d.status == DueStatus.unpaid ||
                    d.status == DueStatus.partiallyPaid ||
                    d.status == DueStatus.overdue,
              )
              .toList();
          final overdue = openDues.where((d) => d.status == DueStatus.overdue);
          final activeCampaigns = (campaigns.valueOrNull ?? const <Campaign>[])
              .where((c) => c.status == CampaignStatus.active)
              .length;
          final upcoming = (events.valueOrNull ?? const <ClubEvent>[])
              .where((e) => e.status == EventStatus.published)
              .length;
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (var i = 0; i < totals.length; i++)
                      _KindCard(
                        total: totals[i],
                        month: monthTotals[i],
                        monthLabel: periodLabelTr(month),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Durum özeti',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    _StatCard(
                      title: 'Açık aidat borcu',
                      value: moneyText(
                        openDues.fold<int>(0, (s, d) => s + d.remainingMinor),
                      ),
                      note: '${openDues.length} borç',
                    ),
                    _StatCard(
                      title: 'Gecikmiş aidat',
                      value: '${overdue.length}',
                      note: moneyText(
                        overdue.fold<int>(0, (s, d) => s + d.remainingMinor),
                      ),
                      tone: overdue.isEmpty
                          ? null
                          : const Color(BrandColors.error),
                    ),
                    _StatCard(
                      title: 'Aktif kampanya',
                      value: '$activeCampaigns',
                    ),
                    _StatCard(
                      title: 'Yayındaki etkinlik',
                      value: '$upcoming',
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _KindCard extends StatelessWidget {
  const _KindCard({
    required this.total,
    required this.month,
    required this.monthLabel,
  });

  final KindTotals total;
  final KindTotals month;
  final String monthLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                total.kind.labelTr,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                moneyText(total.netMinor),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: const Color(BrandColors.navy),
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const Text('Net (iade düşülmüş)', style: TextStyle(fontSize: 12)),
              const Divider(height: 24),
              _line('Brüt tahsilat', moneyText(total.collectedMinor)),
              _line('İade', '-${moneyText(total.refundedMinor)}'),
              _line('İşlem sayısı', '${total.count}'),
              _line('$monthLabel (net)', moneyText(month.netMinor)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label)),
            const SizedBox(width: 12),
            Flexible(child: Text(value, textAlign: TextAlign.end)),
          ],
        ),
      );
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    this.note,
    this.tone,
  });

  final String title;
  final String value;
  final String? note;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title),
              const SizedBox(height: 6),
              Text(
                value,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(color: tone, fontWeight: FontWeight.bold),
              ),
              if (note != null) Text(note!, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
