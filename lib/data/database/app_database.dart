import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/ledger/domain/default_categories.dart';
import '../../features/ledger/domain/entry_kind.dart';

part 'app_database.g.dart';

class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  TextColumn get kind => text()();
  TextColumn get channel => text()();
  TextColumn get currency => text()();
  TextColumn get avatar => text().withDefault(const Constant(''))();
  TextColumn get bank => text().withDefault(const Constant(''))();
  TextColumn get customChannel => text().withDefault(const Constant(''))();
  TextColumn get unitPrice => text().nullable()();
  IntColumn get openingBalance => integer().withDefault(const Constant(0))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryKey => {id};
}

class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 40)();
  TextColumn get kind => text()();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<Set<Column>> get uniqueKeys => [
    {name, kind},
  ];
}

class Entries extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text()();
  IntColumn get amount =>
      integer().customConstraint('NOT NULL CHECK (amount > 0)')();
  TextColumn get accountId => text().references(Accounts, #id)();
  TextColumn get targetAccountId =>
      text().nullable().references(Accounts, #id)();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  TextColumn get debtId => text().nullable().references(Entries, #id)();
  TextColumn get counterparty => text().withDefault(const Constant(''))();
  TextColumn get debtAccountId => text().nullable().references(Accounts, #id)();
  TextColumn get date => text()();
  TextColumn get note => text().withDefault(const Constant(''))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  @override
  Set<Column> get primaryKey => {id};
}

class Budgets extends Table {
  TextColumn get month => text()();
  TextColumn get currency => text()();
  IntColumn get amount =>
      integer().customConstraint('NOT NULL CHECK (amount >= 0)')();
  @override
  Set<Column> get primaryKey => {month, currency};
}

class Items extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get category => text().withDefault(const Constant('未分类'))();
  TextColumn get useType => text().withDefault(const Constant('durable'))();
  TextColumn get status => text().withDefault(const Constant('active'))();
  TextColumn get archivedOn => text().nullable()();
  TextColumn get quantity => text().nullable()();
  TextColumn get unit => text().nullable()();
  IntColumn get price =>
      integer().nullable().customConstraint('CHECK (price >= 0)')();
  TextColumn get currency => text()();
  TextColumn get purchasedOn => text().nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get photo => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  @override
  Set<Column> get primaryKey => {id};
}

class PurchaseLinks extends Table {
  TextColumn get itemId =>
      text().references(Items, #id, onDelete: KeyAction.cascade)();
  TextColumn get entryId =>
      text().references(Entries, #id, onDelete: KeyAction.cascade)();
  @override
  Set<Column> get primaryKey => {itemId, entryId};
}

class Preferences extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column> get primaryKey => {key};
}

class BalanceAdjustments extends Table {
  TextColumn get id => text()();
  TextColumn get accountId =>
      text().references(Accounts, #id, onDelete: KeyAction.cascade)();
  IntColumn get beforeBalance => integer()();
  IntColumn get afterBalance => integer()();
  IntColumn get delta => integer()();
  TextColumn get date => text()();
  TextColumn get reason => text().withDefault(const Constant(''))();
  IntColumn get createdAt => integer()();
  @override
  Set<Column> get primaryKey => {id};
}

class WishGoals extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get kind => text().withDefault(const Constant('wish'))();
  TextColumn get currency => text()();
  IntColumn get target =>
      integer().customConstraint('NOT NULL CHECK (target > 0)')();
  TextColumn get deadline => text().nullable()();
  IntColumn get priority => integer().withDefault(const Constant(1))();
  TextColumn get status => text().withDefault(const Constant('active'))();
  TextColumn get note => text().withDefault(const Constant(''))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  @override
  Set<Column> get primaryKey => {id};
}

class GoalContributions extends Table {
  TextColumn get id => text()();
  TextColumn get goalId =>
      text().references(WishGoals, #id, onDelete: KeyAction.cascade)();
  IntColumn get amount =>
      integer().customConstraint('NOT NULL CHECK (amount <> 0)')();
  TextColumn get date => text()();
  TextColumn get note => text().withDefault(const Constant(''))();
  IntColumn get createdAt => integer()();
  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    Accounts,
    Categories,
    Entries,
    Budgets,
    Items,
    PurchaseLinks,
    Preferences,
    BalanceAdjustments,
    WishGoals,
    GoalContributions,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(
        executor ??
            driftDatabase(
              name: 'so_account',
              native: const DriftNativeOptions(
                databaseDirectory: getApplicationSupportDirectory,
              ),
            ),
      );

  @override
  int get schemaVersion => 9;

  Future<void> migrateDebtAccounts() async {
    for (final account in await select(accounts).get()) {
      final type = normalizeAccountType(
        account.kind,
        account.channel,
        account.customChannel,
      );
      await (update(accounts)..where((a) => a.id.equals(account.id))).write(
        AccountsCompanion(
          kind: Value(type.kind),
          channel: Value(type.channel),
          customChannel: Value(type.custom),
        ),
      );
    }
    final principals =
        await (select(entries)..where(
              (e) => e.kind.isIn(['borrow', 'lend']) & e.debtAccountId.isNull(),
            ))
            .get();
    for (final debt in principals) {
      final fund = await (select(
        accounts,
      )..where((a) => a.id.equals(debt.accountId))).getSingle();
      final side = debt.kind == 'borrow' ? '应付款' : '应收款';
      final name = debt.counterparty.isEmpty ? '未注明往来人' : debt.counterparty;
      var account =
          await (select(accounts)..where(
                (a) =>
                    a.kind.equals('债务') &
                    a.channel.equals(side) &
                    a.currency.equals(fund.currency) &
                    a.name.equals(name),
              ))
              .getSingleOrNull();
      if (account == null) {
        final id =
            'legacy-debt-${debt.kind}-${fund.currency}-${Uri.encodeComponent(name)}';
        await into(accounts).insert(
          AccountsCompanion.insert(
            id: id,
            name: name,
            kind: '债务',
            channel: side,
            currency: fund.currency,
          ),
        );
        account = await (select(
          accounts,
        )..where((a) => a.id.equals(id))).getSingle();
      }
      await (update(
        entries,
      )..where((e) => e.id.equals(debt.id) | e.debtId.equals(debt.id))).write(
        EntriesCompanion(
          debtAccountId: Value(account.id),
          counterparty: Value(account.name),
        ),
      );
    }
  }

  Future<void> seedDefaults({bool upgrade = false}) async {
    for (final (kind, names) in [
      ('expense', expenseDefaults),
      ('income', incomeDefaults),
    ]) {
      for (var i = 0; i < names.length; i++) {
        final existing = await (select(
          categories,
        )..where((c) => c.kind.equals(kind) & c.name.equals(names[i]))).get();
        if (existing.isEmpty) {
          await into(categories).insert(
            CategoriesCompanion.insert(
              id: '${upgrade ? 'default-v2-' : ''}$kind-$i',
              name: names[i],
              kind: kind,
            ),
          );
        }
      }
    }
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement('CREATE INDEX entries_date ON entries(date)');
      await customStatement(
        'CREATE INDEX goal_contributions_goal ON goal_contributions(goal_id)',
      );
      await customStatement(
        'CREATE INDEX balance_adjustments_account ON balance_adjustments(account_id)',
      );
      await customStatement(
        'CREATE INDEX entries_account ON entries(account_id)',
      );
      await seedDefaults();
    },
    onUpgrade: (m, from, to) async {
      // Historical debt migrations read Accounts using the current generated
      // model, so new fields must exist before those reads.
      if (from < 9) {
        await m.addColumn(accounts, accounts.isArchived);
      }
      if (from < 8) {
        await m.addColumn(accounts, accounts.bank);
      }
      if (from < 2) {
        await m.addColumn(accounts, accounts.avatar);
        await m.addColumn(items, items.useType);
        await m.addColumn(items, items.status);
        await m.addColumn(items, items.archivedOn);
        // Preserve used or renamed legacy categories and their stable IDs.
        for (final (kind, names) in [
          ('expense', ['饮食', '交通', '购物', '生活', '住房', '医疗', '娱乐', '其他支出']),
          ('income', ['工资', '奖金', '理财收益', '其他收入']),
        ]) {
          for (var i = 0; i < names.length; i++) {
            await customStatement(
              'DELETE FROM categories WHERE id = ? AND name = ? AND NOT EXISTS (SELECT 1 FROM entries WHERE category_id = categories.id)',
              ['$kind-$i', names[i]],
            );
          }
        }
        await seedDefaults(upgrade: true);
      }
      if (from < 3) {
        await m.addColumn(items, items.quantity);
        await m.addColumn(items, items.unit);
        await customStatement(
          "UPDATE items SET status = 'completed' WHERE status IN ('retired', 'depleted')",
        );
      }
      if (from < 4) {
        await m.addColumn(entries, entries.counterparty);
      }
      if (from < 5) {
        await m.addColumn(accounts, accounts.customChannel);
        await m.addColumn(accounts, accounts.unitPrice);
        await m.addColumn(entries, entries.debtAccountId);
        await migrateDebtAccounts();
      }
      if (from < 6) {
        await m.createTable(balanceAdjustments);
        await customStatement(
          'CREATE INDEX balance_adjustments_account ON balance_adjustments(account_id)',
        );
      }
      if (from < 7) {
        await m.createTable(wishGoals);
        await m.createTable(goalContributions);
        await customStatement(
          'CREATE INDEX goal_contributions_goal ON goal_contributions(goal_id)',
        );
      }
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
      // Data-only upgrade: never restore categories that a user later deletes.
      await transaction(() async {
        const key = 'category_defaults_20261025';
        if (await (select(
              preferences,
            )..where((p) => p.key.equals(key))).getSingleOrNull() !=
            null) {
          return;
        }
        for (final (kind, names) in [
          ('expense', additionalExpenseDefaults),
          ('income', additionalIncomeDefaults),
        ]) {
          for (final name in names) {
            final existing = await (select(
              categories,
            )..where((c) => c.kind.equals(kind) & c.name.equals(name))).get();
            if (existing.isEmpty) {
              await into(categories).insert(
                CategoriesCompanion.insert(
                  id: 'default-20261025-$kind-$name',
                  name: name,
                  kind: kind,
                ),
              );
            }
          }
        }
        await into(preferences)
            .insert(PreferencesCompanion.insert(key: key, value: 'done'));
      });
    },
  );
}
