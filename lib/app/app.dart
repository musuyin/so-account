import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers/providers.dart';
import 'theme/app_theme.dart';
import '../features/ledger/presentation/home_page.dart';
import '../features/ledger/presentation/accounts_page.dart';
import '../features/inventory/presentation/inventory_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/statistics/presentation/statistics_page.dart';

final routerProvider = Provider((ref) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
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
    final mode =
        ref.watch(snapshotProvider).value?.preference('theme', 'system') ??
        'system';
    return MaterialApp.router(
      title: '素帐',
      debugShowCheckedModeBanner: false,
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
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
          child: child,
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
