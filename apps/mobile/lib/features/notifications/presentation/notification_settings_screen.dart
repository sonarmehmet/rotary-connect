import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models.dart';
import '../../../data/providers.dart';
import '../../../data/repository.dart';
import '../../../shared/widgets/async_view.dart';
import '../../../shared/widgets/test_data_banner.dart';

/// Bildirim tercihleri. Ödeme sonucu, makbuz ve kayıt onayı gibi işlemsel bildirimler kapatılamaz.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  Future<void> _save(WidgetRef ref, NotificationPrefs p) async {
    await ref.read(repositoryProvider).saveNotificationPrefs(p);
    ref.invalidate(notificationPrefsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text('Bildirim Tercihleri')),
        body: Column(children: [
          const TestDataBanner(),
          Expanded(
            child: AsyncView<NotificationPrefs>(
              value: ref.watch(notificationPrefsProvider),
              isEmpty: (_) => false,
              onRetry: () => ref.invalidate(notificationPrefsProvider),
              builder: (p) => ListView(padding: const EdgeInsets.all(Gaps.md), children: [
                SwitchListTile(title: const Text('Etkinlik bildirimleri'), value: p.events, onChanged: (v) => _save(ref, p.copyWith(events: v))),
                SwitchListTile(title: const Text('Aidat hatırlatmaları'), value: p.dues, onChanged: (v) => _save(ref, p.copyWith(dues: v))),
                SwitchListTile(title: const Text('Bağış bildirimleri'), value: p.donations, onChanged: (v) => _save(ref, p.copyWith(donations: v))),
                SwitchListTile(title: const Text('Duyurular'), value: p.announcements, onChanged: (v) => _save(ref, p.copyWith(announcements: v))),
                const Padding(
                  padding: EdgeInsets.all(Gaps.md),
                  child: Text('Ödeme sonucu ve makbuz bildirimleri güvenlik ve kayıt amacıyla her zaman gönderilir.'),
                ),
              ]),
            ),
          ),
        ]),
      );
}
