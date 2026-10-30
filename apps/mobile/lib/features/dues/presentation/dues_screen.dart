import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models.dart';
import '../../../data/providers.dart';
import '../../../shared/widgets/async_view.dart';
import '../../../shared/widgets/test_data_banner.dart';

class DuesScreen extends ConsumerWidget {
  const DuesScreen({super.key, this.now});

  /// Test için sabit saat; null ise gerçek saat.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final df = DateFormat('d MMMM y', 'tr_TR');
    final clock = now ?? DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('Aidat ve Ödemelerim')),
      body: Column(children: [
        const TestDataBanner(),
        Expanded(
          child: AsyncView<List<DueItem>>(
            value: ref.watch(duesProvider),
            emptyText: 'Aidat kaydınız yok.',
            onRetry: () => ref.invalidate(duesProvider),
            builder: (list) => ListView(padding: const EdgeInsets.all(Gaps.md), children: [
              for (final d in list)
                Card(
                  child: ListTile(
                    title: Text(d.period),
                    subtitle: Text('Son ödeme: ${df.format(d.dueDate)}\nKalan: ${d.remaining.format()}'),
                    isThreeLine: true,
                    trailing: d.isPaid
                        ? const Chip(label: Text('Ödendi'))
                        : Chip(label: Text(d.isOverdue(clock) ? 'Gecikmiş' : 'Bekliyor')),
                  ),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}
