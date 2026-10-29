import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rotary_shared/shared.dart';

import 'core/modules.dart';

/// Geçici rol durumu (Aşama 4'te Firebase Auth claim'inden okunacak).
/// Geliştirme kolaylığı için varsayılan sistem yöneticisidir; üretimde
/// oturum açılmadan panel içeriği gösterilmeyecektir.
final adminRoleProvider = StateProvider<AppRole>((ref) => AppRole.systemAdmin);

final adminRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    routes: [
      ShellRoute(
        builder: (context, state, child) => AdminShell(child: child),
        routes: [
          for (final m in adminModules)
            GoRoute(
              path: m.path,
              builder: (_, __) => _ModulePlaceholder(module: m),
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
        '${module.title} modülü Aşama 3 / 9\'da uygulanacak.',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}
