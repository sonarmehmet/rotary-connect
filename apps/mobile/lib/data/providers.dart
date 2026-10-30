import 'package:rotary_shared/shared.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/router/app_router.dart';
import 'models.dart';
import 'repository.dart';

final campaignsProvider = FutureProvider<List<Campaign>>((ref) => ref.watch(repositoryProvider).campaigns());
final eventsProvider = FutureProvider<List<EventItem>>((ref) => ref.watch(repositoryProvider).events());
final projectsProvider = FutureProvider<List<Project>>((ref) => ref.watch(repositoryProvider).projects());
final newsProvider = FutureProvider<List<NewsItem>>((ref) => ref.watch(repositoryProvider).news());
final notificationsProvider = FutureProvider<List<AppNotification>>((ref) => ref.watch(repositoryProvider).notifications());
final notificationPrefsProvider = FutureProvider<NotificationPrefs>((ref) => ref.watch(repositoryProvider).notificationPrefs());
final notificationPrefsProvider = FutureProvider<NotificationPrefs>((ref) => ref.watch(repositoryProvider).notificationPrefs());
final duesProvider = FutureProvider<List<DueItem>>((ref) => ref.watch(repositoryProvider).myDues());

/// Oturumdaki kullanıcı; null = ziyaretçi. Rol, yönlendirme için [currentRoleProvider]'a yansıtılır.
class SessionController extends StateNotifier<UserProfile?> {
  SessionController(this._ref) : super(null);
  final Ref _ref;

  Future<bool> signIn(String email, String password) async {
    final u = await _ref.read(repositoryProvider).signIn(email, password);
    if (u == null) return false;
    _set(u);
    return true;
  }

  Future<void> register(String name, String email, String password) async =>
      _set(await _ref.read(repositoryProvider).register(name, email, password));

  Future<void> signOut() async {
    await _ref.read(repositoryProvider).signOut();
    state = null;
    _ref.read(currentRoleProvider.notifier).state = AppRole.visitor;
  }

  void _set(UserProfile u) {
    state = u;
    _ref.read(currentRoleProvider.notifier).state = u.role;
  }
}

final sessionProvider = StateNotifierProvider<SessionController, UserProfile?>((ref) => SessionController(ref));
