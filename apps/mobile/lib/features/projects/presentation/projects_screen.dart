import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models.dart';
import '../../../data/providers.dart';
import '../../../shared/widgets/async_view.dart';
import '../../../shared/widgets/test_data_banner.dart';

class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text('Projeler')),
        body: Column(children: [
          const TestDataBanner(),
          Expanded(
            child: AsyncView<List<Project>>(
              value: ref.watch(projectsProvider),
              emptyText: 'Henüz proje yok.',
              onRetry: () => ref.invalidate(projectsProvider),
              builder: (list) => ListView(padding: const EdgeInsets.all(Gaps.md), children: [
                for (final p in list) Card(child: ListTile(title: Text(p.title), subtitle: Text(p.summary), trailing: Chip(label: Text(p.status)))),
              ]),
            ),
          ),
        ]),
      );
}
