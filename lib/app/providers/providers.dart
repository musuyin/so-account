import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/app_snapshot.dart';
export '../../data/app_snapshot.dart';
import '../../features/ledger/data/ledger_repository.dart';
import '../../features/ledger/data/ledger_read_repository.dart';
export '../../features/ledger/data/ledger_read_repository.dart';
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
final preferencesProvider = StreamProvider((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.preferences).watch();
});

final snapshotProvider = StreamProvider.autoDispose((ref) {
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

final homeLedgerProvider = StreamProvider.autoDispose
    .family<HomeLedgerView, HomeQuery>(
      (ref, query) =>
          LedgerReadRepository(ref.watch(databaseProvider)).watchHome(query),
    );
final accountLedgerProvider = StreamProvider.autoDispose
    .family<AccountLedgerView, AccountQuery>(
      (ref, query) =>
          LedgerReadRepository(ref.watch(databaseProvider)).watchAccount(query),
    );
