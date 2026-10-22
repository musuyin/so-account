import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/importing/domain/import_plan.dart';
import 'package:so_account/features/importing/domain/import_table.dart';
import 'package:so_account/features/importing/domain/missing_accounts.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/domain/debt_relationship.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';
import 'package:so_account/features/statistics/data/csv_export.dart';

void main() {
  late AppDatabase db;
  late LedgerRepository repo;
  late String cash;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = LedgerRepository(db);
    cash = await repo.saveAccount(
      name: '钱包',
      kind: '资金账户',
      channel: '现金',
      currency: 'CNY',
      openingBalance: 100000,
    );
  });
  tearDown(() => db.close());
  Future<String> debt(EntryKind kind, String person, {int amount = 10000}) =>
      repo.saveEntry(
        kind: kind,
        amount: amount,
        accountId: cash,
        date: '2026-10-01',
        counterparty: person,
      );
  test(
    'people receivables/payables stay separate and settlements inherit person',
    () async {
      final borrowed = await debt(EntryKind.borrow, '小林');
      await debt(EntryKind.lend, '小林', amount: 5000);
      await debt(EntryKind.lend, '小陈');
      await repo.saveEntry(
        kind: EntryKind.repay,
        amount: 2500,
        accountId: cash,
        debtId: borrowed,
        date: '2026-10-02',
      );
      final entries = await db.select(db.entries).get();
      expect(entries.singleWhere((e) => e.kind == 'repay').counterparty, '小林');
      final groups = PersonDebtSummary.group(
        entries,
        await db.select(db.accounts).get(),
      );
      final lin = groups.singleWhere((g) => g.name == '小林');
      expect(lin.receivable, 5000);
      expect(lin.payable, 7500);
      expect((await repo.watchBalances().first)[cash], 92500);
      expect((await db.select(db.accounts).get()).length, 4);
      final csv = readImportTables(
        'export.csv',
        Uint8List.fromList(
          utf8.encode(
            await CsvExport(db).create(ExportPeriod.all, DateTime(2026)),
          ),
        ),
      );
      expect(csv.single.headers.last, '往来人');
    },
  );
  test(
    'wrong person, overpayment and renaming a settled debt fail without writes',
    () async {
      final borrowed = await debt(EntryKind.borrow, '小林');
      await expectLater(
        repo.saveEntry(
          kind: EntryKind.repay,
          amount: 100,
          accountId: cash,
          debtId: borrowed,
          date: '2026-10-02',
          counterparty: '小陈',
        ),
        throwsFormatException,
      );
      await repo.saveEntry(
        kind: EntryKind.repay,
        amount: 1000,
        accountId: cash,
        debtId: borrowed,
        date: '2026-10-02',
      );
      await expectLater(
        repo.saveEntry(
          kind: EntryKind.borrow,
          amount: 10000,
          accountId: cash,
          id: borrowed,
          date: '2026-10-01',
          counterparty: '小陈',
        ),
        throwsFormatException,
      );
      await expectLater(
        repo.saveEntry(
          kind: EntryKind.repay,
          amount: 9001,
          accountId: cash,
          debtId: borrowed,
          date: '2026-10-03',
        ),
        throwsFormatException,
      );
      expect((await db.select(db.entries).get()).length, 2);
    },
  );
  test('legacy unlabelled debts remain compatible and ordinary entries clear person', () async {
    await debt(EntryKind.borrow, '');
    final categories = await db.select(db.categories).get();
    await repo.saveEntry(
      kind: EntryKind.income,
      amount: 100,
      accountId: cash,
      date: '2026-10-01',
      categoryId: categories.firstWhere((c) => c.kind == 'income').id,
      counterparty: '不保留',
    );
    final entries = await db.select(db.entries).get();
    expect(
      entries.singleWhere((e) => e.kind == 'borrow').counterparty,
      '未注明往来人',
    );
    expect(entries.singleWhere((e) => e.kind == 'income').counterparty, '');
  });
  test(
    'personal loan directions never turn a person into a funds account',
    () async {
      for (final (kind, source, target) in [
        ('借入', '小林', '钱包'),
        ('借出', '钱包', '小林'),
        ('偿还借入', '钱包', '小林'),
        ('收回借出', '小林', '钱包'),
      ]) {
        final table = ImportTable.fromRows('test', [
          ['日期', '类型', '转出账户', '转入账户', '金额'],
          ['2026-10-02', kind, source, target, '10'],
        ]);
        final mapping = ImportMapping()..detect(table);
        expect(
          mapping.sourceAccountValue(
            table.rows.single,
            mapping.kindFor(table.rows.single),
          ),
          '钱包',
        );
        expect(
          mapping.counterpartyValue(
            table.rows.single,
            mapping.kindFor(table.rows.single),
          ),
          '小林',
        );
        expect(
          missingImportAccounts(
            table,
            mapping,
            await db.select(db.accounts).get(),
          ),
          isEmpty,
        );
      }
    },
  );
  test('mixed repayment labels allow row-specific meaning without creating people accounts', () async {
    final table = ImportTable.fromRows('转账', [
      ['日期', '类型', '转出账户', '转入账户', '金额'],
      ['2026-10-02', '还款', '钱包', '花呗', '10'],
      ['2026-10-02', '还款', '小林', '钱包', '10'],
    ]);
    final mapping = ImportMapping()..detect(table);
    expect(importAccountSources(table, mapping), isEmpty);
    mapping.kinds['还款'] = 'transfer';
    mapping.rowKinds[table.rows.last] = EntryKind.collect;
    expect(mapping.kindFor(table.rows.first), EntryKind.transfer);
    expect(mapping.kindFor(table.rows.last), EntryKind.collect);
    expect(mapping.counterpartyValue(table.rows.last, EntryKind.collect), '小林');
    expect(importAccountSources(table, mapping).map((a) => a.name), [
      '钱包',
      '花呗',
    ]);
    mapping.detect(table);
    expect(mapping.rowKinds, isEmpty);
    expect(mapping.debts, isEmpty);
  });
  test('repayments require explicit original debt and duplicate identity includes it', () async {
    final first = await debt(EntryKind.borrow, '小林');
    final second = await debt(EntryKind.borrow, '小林');
    final table = ImportTable.fromRows('转账', [
      ['日期', '类型', '转出账户', '转入账户', '金额'],
      ['2026-10-02', '还款', '钱包', '小林', '10'],
      ['2026-10-02', '还款', '钱包', '小林', '10'],
    ]);
    final mapping = ImportMapping()..detect(table);
    mapping.kinds['还款'] = 'repay';
    final accounts = await db.select(db.accounts).get();
    final existing = await db.select(db.entries).get();
    expect(
      eligibleImportDebts(table.rows.first, mapping, accounts, existing).length,
      2,
    );
    expect(
      previewImport(table, mapping, accounts, [], existing).first.error,
      contains('请选择此行对应的原始借贷'),
    );
    mapping.debts[2] = first;
    mapping.debts[3] = second;
    final plan = previewImport(table, mapping, accounts, [], existing);
    expect(plan.map((r) => r.error), everyElement(isNull));
    expect(plan.map((r) => r.entry!.suspectedDuplicate), [false, false]);
    await commitImport(db, plan.map((r) => r.entry!).toList());
    expect(
      (await db.select(db.entries).get())
          .where((e) => e.kind == 'repay')
          .map((e) => e.counterparty),
      ['小林', '小林'],
    );
    expect((await db.select(db.accounts).get()).length, 2);
  });
  test(
    'batch overpayment revalidates transaction and rolls back all repayments',
    () async {
      final original = await debt(EntryKind.borrow, '小林', amount: 1000);
      final table = ImportTable.fromRows('test', [
        ['日期', '类型', '金额', '账户', '往来人', '关联借贷ID'],
        ['2026-10-02', '偿还借入', '6', '钱包', '小林', original],
        ['2026-10-03', '偿还借入', '6', '钱包', '小林', original],
      ]);
      final mapping = ImportMapping()..detect(table);
      final plan = previewImport(
        table,
        mapping,
        await db.select(db.accounts).get(),
        [],
        await db.select(db.entries).get(),
      );
      expect(plan.map((r) => r.error), everyElement(isNull));
      await expectLater(
        commitImport(db, plan.map((r) => r.entry!).toList()),
        throwsFormatException,
      );
      expect((await db.select(db.entries).get()).length, 1);
    },
  );
  test(
    'v3 database upgrades person field without changing money or debt links',
    () async {
      final dir = await Directory.systemTemp.createTemp('so_v3_');
      final file = File('${dir.path}/data.db');
      final old = AppDatabase(NativeDatabase(file));
      try {
        final ledger = LedgerRepository(old);
        final account = await ledger.saveAccount(
          name: '旧钱包',
          kind: '资金账户',
          channel: '现金',
          currency: 'CNY',
          openingBalance: 1000,
        );
        final principal = await ledger.saveEntry(
          kind: EntryKind.borrow,
          amount: 500,
          accountId: account,
          date: '2026-10-01',
        );
        await ledger.saveEntry(
          kind: EntryKind.repay,
          amount: 100,
          accountId: account,
          debtId: principal,
          date: '2026-10-02',
        );
        await old.customStatement(
          'ALTER TABLE entries DROP COLUMN counterparty',
        );
        await old.customStatement(
          'ALTER TABLE entries DROP COLUMN debt_account_id',
        );
        await old.customStatement("DELETE FROM accounts WHERE kind='债务'");
        await old.customStatement(
          'ALTER TABLE accounts DROP COLUMN custom_channel',
        );
        await old.customStatement(
          'ALTER TABLE accounts DROP COLUMN unit_price',
        );
        await old.customStatement('PRAGMA user_version = 3');
        await old.close();
        final next = AppDatabase(NativeDatabase(file));
        try {
          final entries = await next.select(next.entries).get();
          expect(entries.map((e) => e.counterparty), everyElement('未注明往来人'));
          expect(
            entries.singleWhere((e) => e.kind == 'repay').debtId,
            principal,
          );
          expect(
            (await LedgerRepository(next).watchBalances().first)[account],
            1400,
          );
          expect(
            await next.customSelect('PRAGMA foreign_key_check').get(),
            isEmpty,
          );
        } finally {
          await next.close();
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
