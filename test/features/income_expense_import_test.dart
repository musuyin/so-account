import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/importing/domain/import_plan.dart';
import 'package:so_account/features/importing/domain/import_table.dart';
import 'package:so_account/features/importing/domain/missing_accounts.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';

void main() {
  test(
    'income detail falls back when empty and supports explicit remapping',
    () {
      final table = ImportTable.fromRows('synthetic', [
        ['日期', '类型', '金额', '账户', '分类', '二级分类'],
        ['2026-10-23', '收入', '2', '钱包', '收入', '稿酬样例'],
        ['2026-10-23', '收入', '3', '钱包', '奖励样例', ''],
        ['2026-10-23', '支出', '4', '钱包', '交通样例', '子项样例'],
      ]);
      final mapping = IncomeExpenseImportMapping()..detect(table);
      expect(mapping.categoryValuesFor(table, EntryKind.income), {
        '稿酬样例',
        '奖励样例',
      });
      expect(mapping.categoryValuesFor(table, EntryKind.expense), {'交通样例'});
      mapping.columns.remove(ImportField.incomeSubcategory);
      expect(mapping.categoryValuesFor(table, EntryKind.income), {
        '收入',
        '奖励样例',
      });
    },
  );

  test('ignored rows retain source row numbers but never create missing dependencies', () {
    final table = ImportTable.fromRows('mixed', [
      ['日期', '类型', '金额', '账户', '分类'],
      ['bad', '支出', '-0.0000', '零金额账户', '不创建分类'],
      ['bad', '收入', '1', '  ', '不创建分类'],
      ['bad', '转账', '1', '转账账户', '不创建分类'],
      ['2026-10-23', '收入', '2', '钱包', '工资'],
      ['bad', '支出', 'NaN', '钱包', '居住'],
      ['2026-10-23', '未知类型', '12', '钱包', '工资'],
    ]);
    final mapping = IncomeExpenseImportMapping()..detect(table);
    mapping.defaultAccount = 'unused';
    mapping.kinds['转账'] = 'income';
    final result = previewImport(table, mapping, [], [], []);
    expect(result.take(3).map((r) => r.ignoredReason), [
      '零金额',
      '空账户',
      '暂不支持的交易类型',
    ]);
    expect(result.take(3).map((r) => r.error), everyElement(isNull));
    expect(result.map((r) => r.row), [2, 3, 4, 5, 6, 7]);
    expect(result.last.error, '请关联交易类型');
    expect(result.skip(3).every((r) => r.error != null), isTrue);
    expect(importAccountSources(table, mapping).map((s) => s.name), ['钱包']);
    expect(mapping.categoryValuesFor(table, EntryKind.income), {'工资'});
  });

  test(
    'the statement commit rejects transfer or fee data before any write',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final id = await LedgerRepository(db).saveAccount(
        name: '钱包',
        kind: '资金账户',
        channel: '现金',
        currency: 'CNY',
        openingBalance: 0,
      );
      await expectLater(
        commitIncomeExpenseImport(db, [
          ImportEntry(
            row: 2,
            kind: EntryKind.income,
            amount: 100,
            accountId: id,
            date: '2026-10-23',
            note: '',
          ),
          ImportEntry(
            row: 3,
            kind: EntryKind.transfer,
            amount: 100,
            accountId: id,
            date: '2026-10-23',
            note: '',
          ),
        ]),
        throwsFormatException,
      );
      expect(await db.select(db.entries).get(), isEmpty);
    },
  );
}
