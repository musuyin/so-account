import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers/providers.dart';
import 'theme/app_theme.dart';
import 'theme/botanical_surfaces.dart';
import '../core/appearance.dart';
import '../features/ledger/presentation/home_page.dart';
import '../features/ledger/presentation/accounts_page.dart';
import '../features/inventory/presentation/inventory_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/statistics/presentation/statistics_page.dart';
import '../features/updates/presentation/update_page.dart';
import '../features/goals/presentation/goals_page.dart';

final routerProvider = Provider((ref) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/goals', builder: (_, _) => const GoalsPage()),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(path: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const HomePage()),
          GoRoute(path: '/accounts', builder: (_, _) => const AccountsPage()),
          GoRoute(path: '/items', builder: (_, _) => const InventoryPage()),
          GoRoute(
            path: '/statistics',
            builder: (_, _) => const StatisticsPage(),
          ),
          GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class SoAccountApp extends ConsumerWidget {
  const SoAccountApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(preferencesProvider).value ?? [];
    String? preference(String key) =>
        preferences.where((p) => p.key == key).firstOrNull?.value;
    final mode = preference('theme') ?? 'system';
    final palette = AppPalette.parse(preference('palette'));
    final art = ref.watch(botanicalArtProvider).value;
    return MaterialApp.router(
      title: '素帐 · SoAccount',
      debugShowCheckedModeBanner: false,
      theme: appTheme(Brightness.light, palette: palette, art: art),
      darkTheme: appTheme(Brightness.dark, palette: palette, art: art),
      themeMode:
          {'light': ThemeMode.light, 'dark': ThemeMode.dark}[mode] ??
          ThemeMode.system,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(routerProvider),
    );
  }
}

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.path, required this.child});
  final String path;
  final Widget child;
  static const paths = ['/', '/accounts', '/items', '/statistics', '/settings'];
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: UpdateNotice(child: child),
        ),
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: paths.indexOf(path).clamp(0, 4),
      onDestinationSelected: (index) => context.go(paths[index]),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.calendar_month_outlined),
          selectedIcon: Icon(Icons.calendar_month),
          label: '账本',
        ),
        NavigationDestination(
          icon: Icon(Icons.account_balance_wallet_outlined),
          selectedIcon: Icon(Icons.account_balance_wallet),
          label: '账户',
        ),
        NavigationDestination(
          icon: Icon(Icons.inventory_2_outlined),
          selectedIcon: Icon(Icons.inventory_2),
          label: '物品',
        ),
        NavigationDestination(
          icon: Icon(Icons.donut_small_outlined),
          selectedIcon: Icon(Icons.donut_small),
          label: '统计',
        ),
        NavigationDestination(icon: Icon(Icons.tune), label: '设置'),
      ],
    ),
  );
}
