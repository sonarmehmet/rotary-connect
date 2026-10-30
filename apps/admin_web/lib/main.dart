import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rotary_shared/shared.dart';

import 'core/modules.dart';
import 'core/role_provider.dart';
import 'features/audit/audit_page.dart';
import 'features/campaigns/campaigns_page.dart';
import 'features/dues/dues_page.dart';
import 'features/events/events_page.dart';
import 'features/members/members_page.dart';
import 'features/news/news_page.dart';
import 'features/overview/overview_page.dart';
import 'features/payments/payments_page.dart';
import 'features/projects/projects_page.dart';
import 'features/refunds/refunds_page.dart';
import 'features/registrations/registrations_page.dart';
import 'features/reports/reports_page.dart';
import 'features/roles/roles_page.dart';
import 'ui/state_views.dart';

export 'core/role_provider.dart' show adminRoleProvider;

/// Uygulanan modüller. Diğerleri (bildirimler, ayarlar) Dalga 2'de eklenir.
const Map<String, Widget> _pages = {
  '/': OverviewPage(),
  '/members': MembersPage(),
  '/roles': RolesPage(),
  '/registrations': RegistrationsPage(),
  '/dues': DuesPage(),
  '/campaigns': CampaignsPage(),
  '/events': EventsPage(),
  '/projects': ProjectsPage(),
  '/news': NewsPage(),
  '/payments': PaymentsPage(),
  '/refunds': RefundsPage(),
  '/reports': ReportsPage(),
  '/audit': AuditPage(),
};

/// Rota içeriği: yetkisiz rol sayfayı görmez (gerçek yetki sunucudadır).
class _ModuleRoute extends ConsumerWidget {
  const _ModuleRoute({required this.module});

  final AdminModule module;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(adminRoleProvider);
    if (!role.can(module.permission)) return const NoAccessView();
    return _pages[module.path] ?? _ModulePlaceholder(module: module);
  }
}

final adminRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    routes: [
      ShellRoute(
        builder: (context, state, child) => AdminShell(child: child),
        routes: [
          for (final m in adminModules)
            GoRoute(
              path: m.path,
              builder: (_, __) => _ModuleRoute(module: m),
            ),
        ],
      ),
    ],
  );
});

void main() {
  runApp(const ProviderScope(child: AdminApp()));
}

class AdminApp extends ConsumerWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const navy = Color(BrandColors.navy);
    return MaterialApp.router(
      title: 'Rotary Connect Yönetim',
      debugShowCheckedModeBanner: false,
      routerConfig: ref.watch(adminRouterProvider),
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: navy).copyWith(
          primary: navy,
          secondary: const Color(BrandColors.gold),
        ),
        scaffoldBackgroundColor: Colors.white,
      ),
    );
  }
}

class AdminShell extends ConsumerWidget {
  const AdminShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(adminRoleProvider);
    final visible = adminModules.where((m) => role.can(m.permission)).toList();
    final location = GoRouterState.of(context).matchedLocation;
    final selected = visible.indexWhere((m) => m.path == location);
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final destinations = [
      for (final m in visible)
        NavigationRailDestination(
          icon: Icon(m.icon),
          label: Text(m.title),
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rotary Connect • Yönetim Paneli'),
        backgroundColor: const Color(BrandColors.navy),
        foregroundColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: Container(
            width: double.infinity,
            color: const Color(BrandColors.warning),
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: const Text(
              'GELİŞTİRME İSKELETİ • TEST VERİSİ • ÖDEMELER SİMÜLASYON',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
        ),
      ),
      drawer: wide
          ? null
          : Drawer(
              child: ListView(
                children: [
                  for (final m in visible)
                    ListTile(
                      leading: Icon(m.icon),
                      title: Text(m.title),
                      selected: m.path == location,
                      onTap: () {
                        Navigator.of(context).pop();
                        context.go(m.path);
                      },
                    ),
                ],
              ),
            ),
      body: Row(
        children: [
          if (wide && visible.isNotEmpty)
            NavigationRail(
              extended: true,
              selectedIndex: selected < 0 ? null : selected,
              onDestinationSelected: (i) => context.go(visible[i].path),
              destinations: destinations,
            ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _ModulePlaceholder extends StatelessWidget {
  const _ModulePlaceholder({required this.module});

  final AdminModule module;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '${module.title} modülü Dalga 2\'de gerçek veriye bağlanırken eklenecek.',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}
