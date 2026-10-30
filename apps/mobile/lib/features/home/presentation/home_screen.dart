import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rotary_shared/shared.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models.dart';
import '../../../data/providers.dart';
import '../../../shared/widgets/brand_logo.dart';
import '../../../shared/widgets/test_data_banner.dart';

/// Ana sayfa: kampanya, etkinlik ve haber özeti. Rol bazlı görünürlük kuralı burada gösterilmiştir: aidat
/// kısayolu yalnızca `viewOwnDues` iznine sahip rollere çizilir.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(currentRoleProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const TestDataBanner(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(Gaps.md),
                children: [
                  Row(
                    children: [
                      const BrandLogo(size: 56),
                      const SizedBox(width: Gaps.md),
                      Expanded(
                        child: Text(
                          'Rotary Connect',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Gaps.lg),
                  FilledButton.icon(
                    onPressed: () => context.go(Routes.donate),
                    icon: const Icon(Icons.volunteer_activism),
                    label: const Text('Bağış Yap'),
                  ),
                  if (role.can(Permission.viewOwnDues)) ...[
                    const SizedBox(height: Gaps.sm),
                    OutlinedButton.icon(
                      onPressed: () => context.go(Routes.dues),
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('Aidat ve Ödemelerim'),
                    ),
                  ],
                  const SizedBox(height: Gaps.lg),
                  _Section(
                    title: 'Öne çıkan kampanya',
                    child: ref.watch(campaignsProvider).maybeWhen(
                          data: (l) {
                            final a = l.where((c) => c.active).toList();
                            if (a.isEmpty) return const Text('Şu an aktif kampanya yok.');
                            final c = a.first;
                            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(c.title, style: Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: Gaps.xs),
                              LinearProgressIndicator(value: c.progress),
                              Text('${c.verifiedTotal.format()} / ${c.goal.format()}'),
                            ]);
                          },
                          orElse: () => const LinearProgressIndicator(),
                        ),
                  ),
                  _Section(
                    title: 'Yaklaşan etkinlik',
                    onTap: () => context.go(Routes.events),
                    child: ref.watch(eventsProvider).maybeWhen(
                          data: (l) {
                            if (l.isEmpty) return const Text('Yaklaşan etkinlik yok.');
                            final e = ([...l]..sort((a, b) => a.startsAt.compareTo(b.startsAt))).first;
                            return Text(e.title);
                          },
                          orElse: () => const LinearProgressIndicator(),
                        ),
                  ),
                  _Section(
                    title: 'Son haber',
                    onTap: () => context.go(Routes.news),
                    child: ref.watch(newsProvider).maybeWhen(
                          data: (l) => Text(l.isEmpty ? 'Henüz haber yok.' : l.first.title),
                          orElse: () => const LinearProgressIndicator(),
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.onTap});
  final String title;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Gaps.md),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: Gaps.xs),
              child,
            ]),
          ),
        ),
      );
}
