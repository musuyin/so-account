// Local-only acceptance. Pass --dart-define=LEDGER_IMPORT_REFERENCE=<xlsx path>.
// Source accounts, categories, notes and amounts are never printed or exported.
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/importing/domain/import_plan.dart';
import 'package:so_account/features/importing/domain/import_table.dart';
import 'package:so_account/features/importing/domain/import_template.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';

void main() {
  const reference = String.fromEnvironment('LEDGER_IMPORT_REFERENCE');
  test('flat reference workbook parses and imports into an isolated database', () async {
    final file = File(reference);
    final table = readImportTables(file.path, file.readAsBytesSync()).single;
    expect(table.headers, importTemplateHeaders);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LedgerRepository(db);
    final mapping = IncomeExpenseImportMapping()..detect(table);
    var accountIndex = 0;
    for (final row in table.rows.where(
      (r) => mapping.ignoredReason(r) == null,
    )) {
      final name = mapping.value(row, ImportField.account);
      if (mapping.accounts.containsKey(name)) continue;
      mapping.accounts[name] = await repo.saveAccount(
        name: '参考账户${accountIndex++}',
        kind: '资金账户',
        channel: '现金',
        currency: 'CNY',
        openingBalance: 0,
      );
    }
    var categoryIndex = 0;
    for (final kind in [EntryKind.income, EntryKind.expense]) {
      for (final name in mapping.categoryValuesFor(table, kind)) {
        await repo.saveCategory('参考分类$categoryIndex', kind.name);
        final category = (await db.select(db.categories).get()).singleWhere(
          (c) => c.name == '参考分类$categoryIndex',
        );
        mapping.categories['${kind.name}:$name'] = category.id;
        categoryIndex++;
      }
    }
    final accounts = await db.select(db.accounts).get();
    final categories = await db.select(db.categories).get();
    final plan = previewImport(table, mapping, accounts, categories, []);
    expect(plan.where((r) => r.error != null), isEmpty);
    final valid = plan
        .where((r) => r.entry != null)
        .map((r) => r.entry!)
        .toList();
    expect(
      valid.every(
        (e) => e.kind.needsCategory && e.fee == null && e.targetId == null,
      ),
      isTrue,
    );
    expect(await commitIncomeExpenseImport(db, valid), valid.length);
    expect((await db.select(db.entries).get()).length, valid.length);
    for (final entry in valid) {
      final row = table.rows[entry.row - 2];
      final name = mapping.value(row, ImportField.category);
      expect(entry.categoryId, mapping.categories['${entry.kind.name}:$name']);
      expect(entry.date, importDate(mapping.value(row, ImportField.date)));
      expect(entry.note, mapping.value(row, ImportField.note));
    }
    final ignored = <String, int>{};
    for (final result in plan.where((r) => r.ignored)) {
      ignored.update(result.ignoredReason!, (v) => v + 1, ifAbsent: () => 1);
    }
    print(
      'rows=${table.rows.length}, imported=${valid.length}, income=${valid.where((e) => e.kind == EntryKind.income).length}, ignored=$ignored',
    );
  }, skip: reference.isEmpty ? 'No local reference workbook specified' : false);
}
