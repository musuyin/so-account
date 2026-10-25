import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/backup/data/backup_service.dart';
import 'package:so_account/features/importing/domain/import_plan.dart';
import 'package:so_account/features/importing/domain/import_table.dart';
import 'package:so_account/features/importing/domain/missing_accounts.dart';
import 'package:so_account/features/inventory/domain/new_purchase_item.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';
import 'package:so_account/features/statistics/data/csv_export.dart';
import 'package:so_account/platform/media/media_store.dart';

void main() {
  late AppDatabase db;
  late LedgerRepository repo;
  late String cash, other;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = LedgerRepository(db);
    cash = await repo.saveAccount(
      name: '合成钱包',
      kind: '资金账户',
      channel: '现金',
      currency: 'CNY',
      openingBalance: 10000,
    );
    other = await repo.saveAccount(
      name: '合成银行卡',
      kind: '资金账户',
      channel: '银行卡',
      currency: 'CNY',
      openingBalance: 5000,
    );
  });
  tearDown(() => db.close());

  Future<String> expense({bool item = false}) => repo.saveEntry(
    kind: EntryKind.expense,
    amount: 500,
    accountId: cash,
    categoryId: 'expense-0',
    date: '2026-10-01',
    note: '合成历史支出',
    newItem: item
        ? const NewPurchaseItem(name: '合成物品', category: '数码产品', price: 500)
        : null,
  );

  test('archive preserves history, balances, monthly totals and CSV; restore keeps identity', () async {
    final entryId = await expense(item: true);
    await repo.adjustBalance(
      accountId: cash,
      desiredBalance: 9600,
      expectedBalance: 9500,
    );
    final entries = await db.select(db.entries).get();
    final links = await db.select(db.purchaseLinks).get();
    final adjustments = await db.select(db.balanceAdjustments).get();
    final balances = await repo.balances();
    final csv = await CsvExport(db)
        .create(ExportPeriod.all, DateTime(2026, 10));

    await repo.archiveAccount(cash);
    expect(
      (await db.select(db.accounts).get())
          .firstWhere((a) => a.id == cash)
          .isArchived,
      isTrue,
    );
    expect(await db.select(db.entries).get(), entries);
    expect(await db.select(db.purchaseLinks).get(), links);
    expect(await db.select(db.balanceAdjustments).get(), adjustments);
    expect(await repo.balances(), balances);
    expect((await repo.watchMonthly('2026-10').first).single.amount, 500);
    expect(
      await CsvExport(db).create(ExportPeriod.all, DateTime(2026, 10)),
      csv,
    );
    await expectLater(expense(), throwsFormatException);
    await expectLater(repo.deleteEntry(entryId), throwsFormatException);
    await expectLater(
      repo.adjustBalance(
        accountId: cash,
        desiredBalance: 0,
        expectedBalance: 9600,
      ),
      throwsFormatException,
    );
    await expectLater(
      repo.saveAccount(
        name: '合成钱包',
        kind: '资金账户',
        channel: '现金',
        currency: 'CNY',
        openingBalance: 0,
      ),
      throwsFormatException,
    );
    await expectLater(
      repo.saveAccount(
        id: cash,
        name: '改名',
        kind: '资金账户',
        channel: '现金',
        currency: 'CNY',
        openingBalance: 10000,
      ),
      throwsFormatException,
    );

    await repo.restoreAccount(cash);
    expect(
      (await db.select(db.accounts).get())
          .firstWhere((a) => a.id == cash)
          .isArchived,
      isFalse,
    );
    expect(await repo.balances(), balances);
    await expense();
    expect((await db.select(db.entries).get()).length, 2);
  });

  test('archived transfer targets and debt principals cannot be used or silently reassigned', () async {
    final principal = await repo.saveEntry(
      kind: EntryKind.borrow,
      amount: 2000,
      accountId: cash,
      counterparty: '合成往来人',
      date: '2026-10-01',
    );
    final debt = (await db.select(db.entries).get()).single.debtAccountId!;
    await repo.archiveAccount(other);
    await expectLater(
      repo.saveEntry(
        kind: EntryKind.transfer,
        amount: 100,
        accountId: cash,
        targetAccountId: other,
        date: '2026-10-02',
      ),
      throwsFormatException,
    );
    await repo.archiveAccount(debt);
    await expectLater(
      repo.saveEntry(
        kind: EntryKind.borrow,
        amount: 100,
        accountId: cash,
        counterparty: '合成往来人',
        date: '2026-10-02',
      ),
      throwsFormatException,
    );
    await expectLater(
      repo.saveEntry(
        kind: EntryKind.repay,
        amount: 100,
        accountId: cash,
        debtId: principal,
        date: '2026-10-02',
      ),
      throwsFormatException,
    );
    await expectLater(
      repo.saveEntry(
        id: principal,
        kind: EntryKind.income,
        amount: 2000,
        accountId: cash,
        categoryId: 'income-0',
        date: '2026-10-01',
      ),
      throwsFormatException,
    );
    await repo.restoreAccount(debt);
    await repo.archiveAccount(cash);
    await repo.restoreAccount(other);
    await expectLater(
      repo.saveEntry(
        kind: EntryKind.repay,
        amount: 100,
        accountId: other,
        debtId: principal,
        date: '2026-10-02',
      ),
      throwsFormatException,
    );
  });

  for (final deleteDebt in [false, true]) {
    test(
      'permanent delete cleans transfers, adjustments, purchase links and dependent settlements (debt=$deleteDebt)',
      () async {
        await expense(item: true);
        await repo.adjustBalance(
          accountId: cash,
          desiredBalance: 9600,
          expectedBalance: 9500,
        );
        await repo.saveEntry(
          kind: EntryKind.transfer,
          amount: 1000,
          accountId: other,
          targetAccountId: cash,
          date: '2026-10-02',
        );
        final principal = await repo.saveEntry(
          kind: EntryKind.borrow,
          amount: 2000,
          accountId: cash,
          counterparty: '合成往来人',
          date: '2026-10-01',
        );
        final debt = (await db.select(db.accounts).get())
            .singleWhere((a) => a.kind == '债务')
            .id;
        await repo.saveEntry(
          kind: EntryKind.repay,
          amount: 100,
          accountId: other,
          debtId: principal,
          date: '2026-10-02',
        );
        final unaffected = await repo.saveEntry(
          kind: EntryKind.income,
          amount: 200,
          accountId: other,
          categoryId: 'income-0',
          date: '2026-10-03',
        );
        if (deleteDebt) {
          await repo.deleteAccount(debt);
          expect(
            (await db.select(db.entries).get()).map((e) => e.kind),
            isNot(contains('borrow')),
          );
          expect(
            (await db.select(db.entries).get()).map((e) => e.kind),
            isNot(contains('repay')),
          );
        }
        await repo.archiveAccount(cash);
        await repo.deleteAccount(cash);
        expect((await db.select(db.entries).get()).single.id, unaffected);
        expect(await db.select(db.balanceAdjustments).get(), isEmpty);
        expect(await db.select(db.purchaseLinks).get(), isEmpty);
        expect((await db.select(db.items).get()).single.name, '合成物品');
        expect((await repo.balances())[other], 5200);
        expect(
          await db.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      },
    );
  }

  test('archive survives full backup', () async {
    final root = await Directory.systemTemp.createTemp('so_archive_backup_');
    addTearDown(() => root.delete(recursive: true));
    await expense(item: true);
    final principal = await repo.saveEntry(
      kind: EntryKind.borrow,
      amount: 2000,
      accountId: cash,
      counterparty: '合成往来人',
      date: '2026-10-01',
    );
    await repo.saveEntry(
      kind: EntryKind.repay,
      amount: 500,
      accountId: other,
      debtId: principal,
      date: '2026-10-02',
    );
    final debt = (await db.select(db.accounts).get())
        .singleWhere((a) => a.kind == '债务')
        .id;
    await repo.adjustBalance(
      accountId: cash,
      desiredBalance: 11600,
      expectedBalance: 11500,
    );
    await repo.archiveAccount(cash);
    await repo.archiveAccount(debt);
    final balances = await repo.balances();
    final entries = await db.select(db.entries).get();
    final backup = BackupService(db, MediaStore(root));
    final bytes = await backup.export();
    await repo.deleteAccount(cash);
    await backup.restore(bytes);
    expect(
      (await db.select(db.accounts).get())
          .where((a) => a.isArchived)
          .map((a) => a.id),
      containsAll([cash, debt]),
    );
    expect(await db.select(db.entries).get(), entries);
    expect(await repo.balances(), balances);
    expect((await db.select(db.purchaseLinks).get()).length, 1);
    await repo.restoreAccount(cash);
    await repo.restoreAccount(debt);
    await repo.saveEntry(
      kind: EntryKind.repay,
      amount: 100,
      accountId: other,
      debtId: principal,
      date: '2026-10-03',
    );
  });

  test(
    'permanent delete rolls back history if account deletion fails',
    () async {
      await expense(item: true);
      await repo.adjustBalance(
        accountId: cash,
        desiredBalance: 9600,
        expectedBalance: 9500,
      );
      await db.customStatement(
        "CREATE TRIGGER reject_account_delete BEFORE DELETE ON accounts BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
      );
      await expectLater(repo.deleteAccount(cash), throwsA(isA<Exception>()));
      expect((await db.select(db.entries).get()).length, 1);
      expect((await db.select(db.balanceAdjustments).get()).length, 1);
      expect((await db.select(db.purchaseLinks).get()).length, 1);
      expect((await repo.balances())[cash], 9600);
    },
  );

  test('import preview excludes archived accounts and commit rejects an archived stale selection atomically', () async {
    final table = ImportTable.fromRows('synthetic', [
      ['日期', '类型', '金额', '账户', '分类'],
      ['2026-10-01', '支出', '1', '合成钱包', '居住'],
    ]);
    final mapping = IncomeExpenseImportMapping()..detect(table);
    mapping.accounts['合成钱包'] = cash;
    mapping.expenseCategory = 'expense-0';
    final categories = await db.select(db.categories).get();
    final plan = previewImport(
      table,
      mapping,
      await db.select(db.accounts).get(),
      categories,
      [],
    );
    expect(plan.single.entry, isNotNull);
    await repo.archiveAccount(cash);
    final accounts = await db.select(db.accounts).get();
    expect(
      previewImport(table, mapping, accounts, categories, []).single.error,
      isNotNull,
    );
    expect(missingImportAccounts(table, mapping, accounts).single.name, '合成钱包');
    await expectLater(
      commitIncomeExpenseImport(db, [
        ImportEntry(
          row: 2,
          kind: EntryKind.expense,
          amount: 100,
          accountId: other,
          currency: 'CNY',
          categoryId: 'expense-0',
          date: '2026-10-01',
          note: '',
        ),
        plan.single.entry!,
      ]),
      throwsFormatException,
    );
    expect(await db.select(db.entries).get(), isEmpty);
  });

  test(
    'v8 upgrade preserves account and history and archive persists on reopen',
    () async {
      final root = await Directory.systemTemp.createTemp('so_archive_migrate_');
      addTearDown(() => root.delete(recursive: true));
      final file = File('${root.path}/v8.db');
      final old = AppDatabase(NativeDatabase(file));
      final oldRepo = LedgerRepository(old);
      final id = await oldRepo.saveAccount(
        name: '合成旧账户',
        kind: '资金账户',
        channel: '现金',
        currency: 'CNY',
        openingBalance: 1000,
      );
      final entry = await oldRepo.saveEntry(
        kind: EntryKind.expense,
        amount: 100,
        accountId: id,
        categoryId: 'expense-0',
        date: '2026-10-01',
      );
      await old.customStatement('ALTER TABLE accounts DROP COLUMN is_archived');
      await old.customStatement('PRAGMA user_version = 8');
      await old.close();
      final next = AppDatabase(NativeDatabase(file));
      try {
        expect(
          (await next.select(next.accounts).get()).single.isArchived,
          isFalse,
        );
        expect((await next.select(next.entries).get()).single.id, entry);
        expect((await LedgerRepository(next).balances())[id], 900);
        await LedgerRepository(next).archiveAccount(id);
        expect(
          await next.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      } finally {
        await next.close();
      }
      final reopened = AppDatabase(NativeDatabase(file));
      try {
        expect(
          (await reopened.select(reopened.accounts).get()).single.isArchived,
          isTrue,
        );
        await LedgerRepository(reopened).restoreAccount(id);
        expect((await LedgerRepository(reopened).balances())[id], 900);
      } finally {
        await reopened.close();
      }
    },
  );
}
