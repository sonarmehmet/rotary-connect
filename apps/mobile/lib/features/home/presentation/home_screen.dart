import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rotary_shared/shared.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/brand_logo.dart';
import '../../../shared/widgets/test_data_banner.dart';

/// Aşama 2: yalnızca iskelet. Kampanya/etkinlik/proje kartları Aşama 3'te
/// eklenecek. Rol bazlı görünürlük kuralı burada gösterilmiştir: aidat
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
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(Gaps.md),
                      child: Text(
                        'Öne çıkan proje, kampanyalar, yaklaşan etkinlikler ve '
                        'haberler Aşama 3\'te eklenecek.',
                      ),
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
