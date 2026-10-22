import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../features/ledger/data/ledger_repository.dart';
import '../../features/inventory/data/inventory_repository.dart';
import '../../features/goals/data/goals_repository.dart';
import '../../platform/media/media_store.dart';
import '../../platform/files/file_delivery.dart';

final fileDeliveryProvider = Provider<FileDelivery>((ref) => FileDelivery());

final mediaProvider = FutureProvider((ref) async {
  final store = await MediaStore.open();
  final db = ref.watch(databaseProvider);
  final items = await db.select(db.items).get();
  // A one-day grace period protects photos belonging to an unfinished form.
  await store.collectOrphans(
    items.map((i) => i.photo).whereType<String>().toSet(),
  );
  return store;
});

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
final ledgerProvider = Provider(
  (ref) => LedgerRepository(ref.watch(databaseProvider)),
);
final inventoryProvider = Provider(
  (ref) => InventoryRepository(ref.watch(databaseProvider)),
);
final goalsProvider = Provider(
  (ref) => GoalsRepository(ref.watch(databaseProvider)),
);
final snapshotProvider = StreamProvider((ref) {
  final db = ref.watch(databaseProvider);
  return db
      .customSelect(
        'SELECT 1',
        readsFrom: {
          db.accounts,
          db.categories,
          db.entries,
          db.budgets,
          db.items,
          db.purchaseLinks,
          db.preferences,
          db.balanceAdjustments,
          db.wishGoals,
          db.goalContributions,
        },
      )
      .watch()
      .asyncMap(
        (_) => db.transaction(
          () async => AppSnapshot(
            await db.select(db.accounts).get(),
            await db.select(db.categories).get(),
            await db.select(db.entries).get(),
            await db.select(db.budgets).get(),
            await db.select(db.items).get(),
            await db.select(db.purchaseLinks).get(),
            await db.select(db.preferences).get(),
            await db.select(db.balanceAdjustments).get(),
            await db.select(db.wishGoals).get(),
            await db.select(db.goalContributions).get(),
          ),
        ),
      );
});
final balancesProvider = StreamProvider(
  (ref) => ref.watch(ledgerProvider).watchBalances(),
);
final monthlyProvider = StreamProvider.family<List<MonthlyTotal>, String>(
  (ref, month) => ref.watch(ledgerProvider).watchMonthly(month),
);

class AppSnapshot {
  const AppSnapshot(
    this.accounts,
    this.categories,
    this.entries,
    this.budgets,
    this.items,
    this.links,
    this.preferences, [
    this.adjustments = const [],
    this.goals = const [],
    this.contributions = const [],
  ]);
  final List<Account> accounts;
  final List<Category> categories;
  final List<Entry> entries;
  final List<Budget> budgets;
  final List<Item> items;
  final List<PurchaseLink> links;
  final List<Preference> preferences;
  final List<BalanceAdjustment> adjustments;
  final List<WishGoal> goals;
  final List<GoalContribution> contributions;
  Account account(String id) => accounts.firstWhere((a) => a.id == id);
  String category(String? id) =>
      categories.where((c) => c.id == id).firstOrNull?.name ?? '往来';
  String preference(String key, String fallback) =>
      preferences.where((p) => p.key == key).firstOrNull?.value ?? fallback;
}
