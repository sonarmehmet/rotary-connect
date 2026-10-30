import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models.dart';
import '../../../data/providers.dart';
import '../../../shared/widgets/async_view.dart';
import '../../../shared/widgets/test_data_banner.dart';

class NewsScreen extends ConsumerWidget {
  const NewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final df = DateFormat('d MMMM y', 'tr_TR');
    return Scaffold(
      appBar: AppBar(title: const Text('Haberler ve Duyurular')),
      body: Column(children: [
        const TestDataBanner(),
        Expanded(
          child: AsyncView<List<NewsItem>>(
            value: ref.watch(newsProvider),
            emptyText: 'Henüz haber yok.',
            onRetry: () => ref.invalidate(newsProvider),
            builder: (list) => ListView(padding: const EdgeInsets.all(Gaps.md), children: [
              for (final n in list)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(Gaps.md),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(n.title, style: Theme.of(context).textTheme.titleMedium),
                      Text(df.format(n.publishedAt), style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: Gaps.sm),
                      Text(n.body),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}
