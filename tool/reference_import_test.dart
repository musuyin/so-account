// Local acceptance check. Private reference workbooks are never committed.
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';
import 'package:so_account/features/importing/domain/import_table.dart';
import 'package:so_account/features/importing/domain/import_plan.dart';
import 'package:so_account/features/importing/domain/missing_accounts.dart';

void main() {
  test('private XLS references preview, commit and detect repeated imports', () async {
    final files = Directory('docs/reference')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.xls'))
        .toList();
    expect(files.length, 2);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LedgerRepository(db);
    for (final file in files) {
      for (final table in readImportTables(file.path, file.readAsBytesSync())) {
        final mapping = IncomeExpenseImportMapping()..detect(table);
        for (final source in importAccountSources(table, mapping)) {
          if ((await db.select(db.accounts).get()).any(
            (a) => a.name == source.name,
          )) {
            continue;
          }
          await repo.saveAccount(
            name: source.name,
            kind: '资金账户',
            channel: '银行卡',
            currency: 'CNY',
            openingBalance: 0,
          );
        }
        for (final kind in [EntryKind.expense, EntryKind.income]) {
          for (final name in mapping.categoryValuesFor(table, kind)) {
            if ((await db.select(db.categories).get()).any(
              (c) => c.kind == kind.name && c.name == name,
            )) {
              continue;
            }
            await repo.saveCategory(name, kind.name);
          }
        }
        final accounts = await db.select(db.accounts).get();
        final categories = await db.select(db.categories).get();
        final plan = previewImport(table, mapping, accounts, categories, []);
        final errors = plan.where((r) => r.error != null).toList();
        expect(errors, isEmpty);
        final ignored = plan.where((r) => r.ignored).toList();
        expect(
          ignored.length,
          table.rows.where((r) => mapping.ignoredReason(r) != null).length,
        );
        final valid = plan.where((r) => r.entry != null).toList();
        for (final result in valid) {
          final entry = result.entry!;
          final row = table.rows[result.row - 2];
          expect(entry.kind, mapping.kindFor(row));
          if (entry.kind.needsCategory) {
            final category = categories.singleWhere(
              (c) => c.id == entry.categoryId,
            );
            expect(category.kind, entry.kind.name);
            expect(category.name, mapping.value(row, ImportField.category));
          }
        }
        final selected = valid
            .map((r) => r.entry!)
            .where((e) => !e.suspectedDuplicate)
            .toList();
        final before = (await db.select(db.entries).get()).length;
        final count = selected.isEmpty
            ? 0
            : await commitIncomeExpenseImport(db, selected);
        expect(count, selected.length);
        final stored = await db.select(db.entries).get();
        expect(
          stored.length - before,
          selected.expand((e) => e.recordsToImport).length,
        );
        final repeat = previewImport(
          table,
          mapping,
          accounts,
          categories,
          stored,
        );
        expect(
          repeat.where((r) => r.entry != null).every((r) => r.entry!.duplicate),
          isTrue,
        );
        final income = valid
            .where((r) => r.entry!.kind == EntryKind.income)
            .length;
        print(
          '${table.name}: ${valid.length} valid rows, ${ignored.length} rows ignored, $income income rows, $count committed records; repeat detection passed',
        );
      }
    }
  });
}
