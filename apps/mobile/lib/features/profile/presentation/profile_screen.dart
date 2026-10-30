import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rotary_shared/shared.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/providers.dart';
import '../../../shared/widgets/test_data_banner.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    final role = ref.watch(currentRoleProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Profilim')),
      body: Column(children: [
        const TestDataBanner(),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(Gaps.md), children: [
            if (user == null) ...[
              const Text('Giriş yapmadınız.'),
              const SizedBox(height: Gaps.sm),
              FilledButton(onPressed: () => context.go(Routes.login), child: const Text('Giriş Yap')),
            ] else ...[
              ListTile(leading: const Icon(Icons.person), title: Text(user.name), subtitle: Text(user.email)),
              if (role.can(Permission.viewOwnDues))
                ListTile(leading: const Icon(Icons.receipt_long_outlined), title: const Text('Aidat ve Ödemelerim'), onTap: () => context.go(Routes.dues)),
              ListTile(leading: const Icon(Icons.newspaper_outlined), title: const Text('Haberler ve Duyurular'), onTap: () => context.go(Routes.news)),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Hesabımı ve verilerimi sil (KVKK)'),
                subtitle: const Text('Talep alınır; yasal saklama yükümlülüğü olan mali kayıtlar silinmez.'),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Silme talebi'),
                    content: const Text('Talebiniz kulübe iletilecek (Aşama 4).'),
                    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tamam'))],
                  ),
                ),
              ),
              const Divider(),
              TextButton(
                onPressed: () async {
                  await ref.read(sessionProvider.notifier).signOut();
                  if (context.mounted) context.go(Routes.home);
                },
                child: const Text('Çıkış yap'),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}
