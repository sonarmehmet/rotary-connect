import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models.dart';
import '../../../data/providers.dart';
import '../../../data/repository.dart';
import '../../../shared/widgets/async_view.dart';
import '../../../shared/widgets/test_data_banner.dart';

/// Bildirim listesi. Bildirimler tutar/ad içermez; dokununca ilgili ekrana gider ve okundu olur.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final df = DateFormat('d MMMM, HH:mm', 'tr_TR');
    return Scaffold(
      appBar: AppBar(title: const Text('Bildirimlerim'), actions: [
        IconButton(tooltip: 'Bildirim tercihleri', icon: const Icon(Icons.tune), onPressed: () => context.go(Routes.notificationSettings)),
      ]),
      body: Column(children: [
        const TestDataBanner(),
        Expanded(
          child: AsyncView<List<AppNotification>>(
            value: ref.watch(notificationsProvider),
            emptyText: 'Henüz bildiriminiz yok.',
            onRetry: () => ref.invalidate(notificationsProvider),
            builder: (list) => ListView(padding: const EdgeInsets.all(Gaps.md), children: [
              for (final n in list)
                Card(
                  child: ListTile(
                    leading: Icon(n.read ? Icons.notifications_none : Icons.notifications_active),
                    title: Text(n.title, style: TextStyle(fontWeight: n.read ? FontWeight.normal : FontWeight.bold)),
                    subtitle: Text('${n.body}\n${df.format(n.createdAt)}'),
                    isThreeLine: true,
                    onTap: () async {
                      await ref.read(repositoryProvider).markNotificationRead(n.id);
                      ref.invalidate(notificationsProvider);
                      if (context.mounted) context.go(n.route);
                    },
                  ),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}
