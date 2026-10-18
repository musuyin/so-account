import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/ledger/domain/default_categories.dart';

part 'app_database.g.dart';

class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  TextColumn get kind => text()();
  TextColumn get channel => text()();
  TextColumn get currency => text()();
  TextColumn get avatar => text().withDefault(const Constant(''))();
  IntColumn get openingBalance => integer().withDefault(const Constant(0))();
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

@DriftDatabase(
  tables: [
    Accounts,
    Categories,
    Entries,
    Budgets,
    Items,
    PurchaseLinks,
    Preferences,
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
  int get schemaVersion => 2;

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
        'CREATE INDEX entries_account ON entries(account_id)',
      );
      await seedDefaults();
    },
    onUpgrade: (m, from, to) async {
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
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
