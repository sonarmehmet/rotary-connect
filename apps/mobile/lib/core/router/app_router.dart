import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rotary_shared/shared.dart';

import '../../features/home/presentation/home_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/donations/presentation/donate_screen.dart';
import '../../features/dues/presentation/dues_screen.dart';
import '../../features/events/presentation/events_screen.dart';
import '../../features/news/presentation/news_screen.dart';
import '../../features/notifications/presentation/notification_settings_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/projects/presentation/projects_screen.dart';

/// Geçici (Aşama 2) rol durumu. Aşama 4'te Firebase Auth custom claim'inden
/// okunacak. Burada yalnızca yönlendirme koruma mantığı test edilebilsin diye var.
final currentRoleProvider = StateProvider<AppRole>((ref) => AppRole.visitor);

abstract final class Routes {
  static const home = '/';
  static const donate = '/donate';
  static const events = '/events';
  static const projects = '/projects';
  static const news = '/news';
  static const dues = '/dues';
  static const profile = '/profile';
  static const notifications = '/notifications';
  static const notificationSettings = '/notification-settings';
  static const login = '/login';
  static const register = '/register';
}

final routerProvider = Provider<GoRouter>((ref) {
  final role = ref.watch(currentRoleProvider);

  return GoRouter(
    initialLocation: Routes.home,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      // Arayüz seviyesinde koruma; asıl yetki kontrolü backend'de yapılır.
      if (loc == Routes.dues && !role.can(Permission.viewOwnDues)) {
        return Routes.login;
      }
      if ((loc == Routes.notifications || loc == Routes.notificationSettings) && !role.can(Permission.viewOwnProfile)) {
        return Routes.login;
      }
      if (loc == Routes.profile && !role.can(Permission.viewOwnProfile)) {
        return Routes.login;
      }
      return null;
    },
    routes: [
      ShellRoute(
        builder: (context, state, child) => _MainShell(child: child),
        routes: [
          GoRoute(path: Routes.home, builder: (_, __) => const HomeScreen()),
          GoRoute(
            path: Routes.donate,
            builder: (_, __) => const DonateScreen(),
          ),
          GoRoute(
            path: Routes.events,
            builder: (_, __) => const EventsScreen(),
          ),
          GoRoute(
            path: Routes.projects,
            builder: (_, __) => const ProjectsScreen(),
          ),
          GoRoute(
            path: Routes.profile,
            builder: (_, __) => const ProfileScreen(),
          ),
        ],
      ),
      GoRoute(
        path: Routes.news,
        builder: (_, __) => const NewsScreen(),
      ),
      GoRoute(path: Routes.notificationSettings, builder: (_, __) => const NotificationSettingsScreen()),
      GoRoute(path: Routes.notifications, builder: (_, __) => const NotificationsScreen()),
      GoRoute(
        path: Routes.dues,
        builder: (_, __) => const DuesScreen(),
      ),
      GoRoute(
        path: Routes.login,
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: Routes.register,
        builder: (_, __) => const RegisterScreen(),
      ),
    ],
  );
});

class _MainShell extends StatelessWidget {
  const _MainShell({required this.child});

  final Widget child;

  static const _tabs = <({String path, String label, IconData icon})>[
    (path: Routes.home, label: 'Ana Sayfa', icon: Icons.home_outlined),
    (path: Routes.donate, label: 'Bağış', icon: Icons.volunteer_activism_outlined),
    (path: Routes.events, label: 'Etkinlikler', icon: Icons.event_outlined),
    (path: Routes.projects, label: 'Projeler', icon: Icons.groups_outlined),
    (path: Routes.profile, label: 'Profil', icon: Icons.person_outline),
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    var index = _tabs.indexWhere((t) => t.path == location);
    if (index < 0) index = 0;

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => context.go(_tabs[i].path),
        destinations: [
          for (final t in _tabs)
            NavigationDestination(icon: Icon(t.icon), label: t.label),
        ],
      ),
    );
  }
}
