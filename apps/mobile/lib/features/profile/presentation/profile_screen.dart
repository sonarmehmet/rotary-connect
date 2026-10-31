import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rotary_shared/shared.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/providers.dart';
import '../../../data/repository.dart';
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
              ListTile(leading: const Icon(Icons.notifications_outlined), title: const Text('Bildirimlerim'), onTap: () => context.go(Routes.notifications)),
              ListTile(leading: const Icon(Icons.newspaper_outlined), title: const Text('Haberler ve Duyurular'), onTap: () => context.go(Routes.news)),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Hesabımı ve verilerimi sil (KVKK)'),
                subtitle: const Text('Talep alınır; yasal saklama yükümlülüğü olan mali kayıtlar silinmez.'),
                onTap: () => _requestDeletion(context, ref),
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

Future<void> _requestDeletion(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Hesabı sil'),
      content: const Text('Hesabınız ve kişisel verileriniz silinir. Yasal saklama gereken mali kayıtlar kimliksizleştirilerek tutulur. Devam edilsin mi?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Talep et')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final blockers = await ref.read(repositoryProvider).requestAccountDeletion();
  if (!context.mounted) return;
  const labels = {
    'pending_payments': 'Tamamlanmamış ödemeniz var',
    'outstanding_dues': 'Ödenmemiş aidat borcunuz var',
    'future_event_registrations': 'Gelecek bir etkinlik kaydınız var',
  };
  await showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(blockers.isEmpty ? 'Talep alındı' : 'Şu an silinemez'),
      content: Text(blockers.isEmpty
          ? 'Silme talebiniz alındı; işlem kısa süre içinde tamamlanır.'
          : blockers.map((b) => '• ${labels[b] ?? b}').join('\n')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tamam'))],
    ),
  );
}
