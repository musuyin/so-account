import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';

void main() {
  late AppDatabase db;
  late LedgerRepository repo;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = LedgerRepository(db);
    await repo.saveAccount(
      id: null,
      name: '现金',
      kind: accountKinds.first,
      channel: '现金',
      currency: 'CNY',
      openingBalance: 10000,
    );
    await repo.saveAccount(
      name: '银行',
      kind: accountKinds.first,
      channel: '银行卡',
      currency: 'CNY',
      openingBalance: 0,
    );
    await repo.saveAccount(
      name: '美元',
      kind: accountKinds.first,
      channel: '现金',
      currency: 'USD',
      openingBalance: 0,
    );
  });
  tearDown(() => db.close());
  Future<String> add(
    EntryKind kind,
    int amount, {
    String? target,
    String? debt,
    String date = '2026-10-18',
  }) async {
    final a = (await db.select(db.accounts).get()).first;
    return repo.saveEntry(
      kind: kind,
      amount: amount,
      accountId: a.id,
      targetAccountId: target,
      categoryId: kind.needsCategory ? '${kind.name}-0' : null,
      debtId: debt,
      date: date,
    );
  }

  test('income expense transfer and debts update balances without inflating monthly totals', () async {
    final accounts = await db.select(db.accounts).get();
    await add(EntryKind.income, 5000);
    await add(EntryKind.expense, 1200);
    await add(EntryKind.transfer, 1000, target: accounts[1].id);
    final debt = await add(EntryKind.borrow, 2000);
    await add(EntryKind.repay, 500, debt: debt);
    await add(EntryKind.expense, 999, date: '2026-11-01');
    final totals = await repo.watchMonthly('2026-10').first;
    expect(totals.firstWhere((t) => t.kind == 'income').amount, 5000);
    expect(totals.firstWhere((t) => t.kind == 'expense').amount, 1200);
    final balances = await repo.watchBalances().first;
    expect(balances[accounts[0].id], 13301);
    expect(balances[accounts[1].id], 1000);
    await expectLater(
      add(EntryKind.transfer, 10, target: accounts[2].id),
      throwsFormatException,
    );
  });
  test('settlements cannot overpay, predate or orphan a debt', () async {
    final debt = await add(EntryKind.borrow, 1000);
    await add(EntryKind.repay, 400, debt: debt);
    await expectLater(
      add(EntryKind.repay, 601, debt: debt),
      throwsFormatException,
    );
    await expectLater(
      add(EntryKind.repay, 100, debt: debt, date: '2026-10-17'),
      throwsFormatException,
    );
    await expectLater(repo.deleteEntry(debt), throwsFormatException);
    expect((await db.select(db.entries).get()).length, 2);
  });
  test(
    'foreign keys and used-account edits preserve ledger identity',
    () async {
      final a = (await db.select(db.accounts).get()).first;
      await add(EntryKind.expense, 100);
      await expectLater(repo.deleteAccount(a.id), throwsFormatException);
      await expectLater(
        repo.saveAccount(
          id: a.id,
          name: a.name,
          kind: a.kind,
          channel: a.channel,
          currency: 'USD',
          openingBalance: a.openingBalance,
        ),
        throwsFormatException,
      );
      await expectLater(
        repo.deleteCategory('expense-0'),
        throwsFormatException,
      );
    },
  );
  test('SQLite file survives closing and reopening', () async {
    final dir = await Directory.systemTemp.createTemp('so_account_test_');
    try {
      final file = File('${dir.path}/test.sqlite');
      final first = AppDatabase(NativeDatabase(file));
      await LedgerRepository(first).saveAccount(
        name: '持久化',
        kind: accountKinds.first,
        channel: '现金',
        currency: 'JPY',
        openingBalance: 12,
      );
      await first.close();
      final second = AppDatabase(NativeDatabase(file));
      expect(
        (await second.select(second.accounts).get()).single.openingBalance,
        12,
      );
      await second.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
