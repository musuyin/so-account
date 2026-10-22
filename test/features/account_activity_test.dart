import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/domain/account_activity.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';

void main() {
  test('account activity reconciles both transfer ends, people loans, settlements and balance adjustments', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      final repo = LedgerRepository(db);
      Future<String> account(
        String name,
        String kind,
        String channel,
        int opening,
      ) => repo.saveAccount(
        name: name,
        kind: kind,
        channel: channel,
        currency: 'CNY',
        openingBalance: opening,
      );
      final cash = await account('现金', '资金账户', '现金', 10000);
      final bank = await account('银行卡', '资金账户', '银行卡', 0);
      final payable = await account('期初应付', '债务', '应付款', 5000);
      Future<String> entry(
        EntryKind kind,
        int amount, {
        String? target,
        String? debt,
        String person = '',
      }) => repo.saveEntry(
        kind: kind,
        amount: amount,
        accountId: cash,
        targetAccountId: target,
        debtId: debt,
        counterparty: person,
        categoryId: kind.needsCategory
            ? (kind == EntryKind.income ? 'income-0' : 'expense-0')
            : null,
        date: '2026-10-01',
      );
      await entry(EntryKind.income, 500);
      await entry(EntryKind.expense, 200);
      await entry(EntryKind.transfer, 1000, target: bank);
      final borrow = await entry(EntryKind.borrow, 3000, person: '小明');
      await entry(EntryKind.repay, 1000, debt: borrow);
      final lend = await entry(EntryKind.lend, 1000, person: '小红');
      await entry(EntryKind.collect, 300, debt: lend);
      await entry(EntryKind.transfer, 500, target: payable);
      await repo.adjustBalance(
        accountId: cash,
        desiredBalance: 300,
        expectedBalance: (await repo.balances())[cash]!,
      );
      final balances = await repo.balances();
      final entries = await db.select(db.entries).get();
      final corrections = await db.select(db.balanceAdjustments).get();
      for (final a in await db.select(db.accounts).get()) {
        final rows = accountActivities(a, entries, corrections);
        expect(
          a.openingBalance + rows.fold<int>(0, (sum, r) => sum + r.delta),
          balances[a.id],
          reason: a.name,
        );
      }
      final bankAccount = (await db.select(db.accounts).get()).singleWhere(
        (a) => a.id == bank,
      );
      expect(
        accountActivities(bankAccount, entries, corrections).single.delta,
        1000,
      );
      final payableAccount = (await db.select(db.accounts).get()).singleWhere(
        (a) => a.id == payable,
      );
      expect(
        accountActivities(payableAccount, entries, corrections).single.delta,
        -500,
      );
    } finally {
      await db.close();
    }
  });
}
