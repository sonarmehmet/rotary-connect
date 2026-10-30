import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models.dart';
import '../../../data/providers.dart';
import '../../../data/repository.dart';
import '../../../shared/widgets/async_view.dart';
import '../../../shared/widgets/test_data_banner.dart';

String statusLabel(EventItem e) {
  switch (e.myStatus) {
    case RegistrationStatus.confirmed:
      return 'Kaydınız onaylandı';
    case RegistrationStatus.reserved:
      return 'Yeriniz ayrıldı – ödeme bekleniyor';
    case RegistrationStatus.waitlisted:
      return 'Bekleme listesindesiniz';
    default:
      return e.isFull ? 'Kontenjan doldu' : (e.isFree ? 'Ücretsiz' : e.fee.format());
  }
}

class EventsScreen extends ConsumerWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(eventsProvider);
    final df = DateFormat('d MMMM y, HH:mm', 'tr_TR');
    return Scaffold(
      appBar: AppBar(title: const Text('Etkinlikler')),
      body: Column(children: [
        const TestDataBanner(),
        Expanded(
          child: AsyncView<List<EventItem>>(
            value: events,
            emptyText: 'Yaklaşan etkinlik yok.',
            onRetry: () => ref.invalidate(eventsProvider),
            builder: (list) => ListView(padding: const EdgeInsets.all(Gaps.md), children: [
              for (final e in list)
                Card(
                  child: ListTile(
                    title: Text(e.title),
                    subtitle: Text('${df.format(e.startsAt)}\n${e.location}\n${statusLabel(e)}'),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EventDetailScreen(eventId: e.id))),
                  ),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({super.key, required this.eventId});
  final String eventId;

  Future<void> _act(WidgetRef ref, Future<EventItem> Function() fn) async {
    await fn();
    ref.invalidate(eventsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(eventsProvider);
    final repo = ref.read(repositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Etkinlik')),
      body: AsyncView<List<EventItem>>(
        value: events,
        isEmpty: (_) => false,
        builder: (list) {
          final e = list.firstWhere((x) => x.id == eventId);
          final active = e.myStatus != RegistrationStatus.none && e.myStatus != RegistrationStatus.cancelled;
          return ListView(padding: const EdgeInsets.all(Gaps.md), children: [
            Text(e.title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: Gaps.sm),
            Text(e.description),
            const SizedBox(height: Gaps.md),
            Text('Yer: ${e.location}'),
            Text('Ücret: ${e.isFree ? 'Ücretsiz' : e.fee.format()}'),
            if (e.capacity > 0) Text('Kalan kontenjan: ${e.remaining}'),
            const SizedBox(height: Gaps.sm),
            Text(statusLabel(e), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Gaps.md),
            if (!active)
              FilledButton(
                onPressed: () => _act(ref, () => repo.registerForEvent(e.id)),
                child: Text(e.isFull ? 'Bekleme listesine katıl' : 'Kayıt ol'),
              )
            else
              OutlinedButton(
                onPressed: () => _act(ref, () => repo.cancelEventRegistration(e.id)),
                child: const Text('Kaydı iptal et'),
              ),
          ]);
        },
      ),
    );
  }
}
