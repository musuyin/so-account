import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';
import 'package:so_account/features/ledger/domain/asset_summary.dart';

void main() {
  late AppDatabase db;
  late LedgerRepository repo;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = LedgerRepository(db);
  });
  tearDown(() => db.close());
  Future<String> account(
    String name,
    String kind,
    String channel,
    int opening, {
    String? unitPrice,
  }) => repo.saveAccount(
    name: name,
    kind: kind,
    channel: channel,
    currency: 'CNY',
    openingBalance: opening,
    unitPrice: unitPrice,
  );
  Future<AssetSummary> summary() async {
    final balances = await repo.watchBalances().first;
    return AssetSummary.calculate(
      (await db.select(db.accounts).get()).map(
        (a) => assetBalance(a.channel, balances[a.id]!),
      ),
    );
  }

  test(
    'requested category pairs persist and unit prices remain exact',
    () async {
      for (final group in accountTypes.entries) {
        for (final channel in group.value) {
          await account('${group.key}-$channel', group.key, channel, 100);
        }
      }
      final fund = await account(
        '旧理财',
        '理财账户',
        '其他',
        1234,
        unitPrice: '0.00001234',
      );
      final stored = (await db.select(db.accounts).get()).singleWhere(
        (a) => a.id == fund,
      );
      expect(stored.kind, '投资理财');
      expect(stored.channel, '自定义');
      expect(stored.customChannel, '其他');
      expect(stored.unitPrice, '0.00001234');
      expect(stored.openingBalance, 1234);
      for (final invalid in ['0', '-1', '1.123456789', 'NaN', '10000000000']) {
        await expectLater(
          account('invalid', '投资理财', '股票', 0, unitPrice: invalid),
          throwsFormatException,
        );
      }
      await expectLater(
        account('invalid', '债务', '现金', 0),
        throwsFormatException,
      );
    },
  );
  test(
    'same person can own both debt sides without inflating net assets',
    () async {
      final cash = await account('钱包', '资金账户', '现金', 100000);
      final borrow = await repo.saveEntry(
        kind: EntryKind.borrow,
        amount: 20000,
        accountId: cash,
        date: '2026-10-01',
        counterparty: '小林',
      );
      await repo.saveEntry(
        kind: EntryKind.lend,
        amount: 5000,
        accountId: cash,
        date: '2026-10-02',
        counterparty: '小林',
      );
      await repo.saveEntry(
        kind: EntryKind.repay,
        amount: 3000,
        accountId: cash,
        date: '2026-10-03',
        debtId: borrow,
      );
      expect((await summary()).net, 100000);
      final debts = (await db.select(db.accounts).get())
          .where((a) => a.kind == '债务')
          .toList();
      expect(debts.length, 2);
      final payable = debts.singleWhere((a) => a.channel == '应付款');
      expect((await repo.watchBalances().first)[payable.id], 17000);
      await repo.saveAccount(
        id: payable.id,
        name: '林同学',
        kind: payable.kind,
        channel: payable.channel,
        currency: payable.currency,
        openingBalance: 0,
      );
      final linked = (await db.select(db.entries).get()).where(
        (e) => e.debtAccountId == payable.id,
      );
      expect(linked.map((e) => e.counterparty), everyElement('林同学'));
      expect(linked.singleWhere((e) => e.kind == 'repay').debtId, borrow);
      await expectLater(
        repo.saveEntry(
          kind: EntryKind.transfer,
          amount: 100,
          accountId: cash,
          targetAccountId: payable.id,
          date: '2026-10-04',
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'opening debts settle through transfers and keep net assets invariant',
    () async {
      final cash = await account('钱包', '资金账户', '现金', 100000);
      final payable = await account('小林', '债务', '应付款', 10000);
      final receivable = await account('小林', '债务', '应收款', 5000);
      expect((await summary()).net, 95000);
      await repo.saveEntry(
        kind: EntryKind.transfer,
        amount: 2000,
        accountId: cash,
        targetAccountId: payable,
        date: '2026-10-01',
      );
      await repo.saveEntry(
        kind: EntryKind.transfer,
        amount: 1000,
        accountId: receivable,
        targetAccountId: cash,
        date: '2026-10-01',
      );
      final balances = await repo.watchBalances().first;
      expect(balances[payable], 8000);
      expect(balances[receivable], 4000);
      expect(balances[cash], 99000);
      expect((await summary()).net, 95000);
    },
  );
  test('v4 upgrade preserves loan IDs and creates one debt account per person and side', () async {
    final directory = await Directory.systemTemp.createTemp('so_v4_');
    final file = File('${directory.path}/data.db');
    final old = AppDatabase(NativeDatabase(file));
    final ledger = LedgerRepository(old);
    final cash = await ledger.saveAccount(
      name: '钱包',
      kind: '资金账户',
      channel: '现金',
      currency: 'CNY',
      openingBalance: 100000,
    );
    final loan = await ledger.saveEntry(
      kind: EntryKind.borrow,
      amount: 20000,
      accountId: cash,
      date: '2026-10-01',
      counterparty: '小林',
    );
    await ledger.saveEntry(
      kind: EntryKind.repay,
      amount: 5000,
      accountId: cash,
      date: '2026-10-02',
      debtId: loan,
    );
    await old.customStatement(
      'ALTER TABLE entries DROP COLUMN debt_account_id',
    );
    await old.customStatement("DELETE FROM accounts WHERE kind='债务'");
    await old.customStatement(
      'ALTER TABLE accounts DROP COLUMN custom_channel',
    );
    await old.customStatement('ALTER TABLE accounts DROP COLUMN unit_price');
    await old.customStatement('DROP TABLE balance_adjustments');
    await old.customStatement('PRAGMA user_version=4');
    await old.close();
    final next = AppDatabase(NativeDatabase(file));
    try {
      final accounts = await next.select(next.accounts).get();
      final debt = accounts.singleWhere((a) => a.kind == '债务');
      expect(debt.name, '小林');
      expect(debt.channel, '应付款');
      final entries = await next.select(next.entries).get();
      expect(entries.map((e) => e.debtAccountId), everyElement(debt.id));
      expect(entries.singleWhere((e) => e.kind == 'repay').debtId, loan);
      final balances = await LedgerRepository(next).watchBalances().first;
      expect(balances[debt.id], 15000);
      expect(
        AssetSummary.calculate(
          accounts.map((a) => assetBalance(a.channel, balances[a.id]!)),
        ).net,
        100000,
      );
      await next.migrateDebtAccounts();
      expect((await next.select(next.accounts).get()).length, 2);
      expect(
        await next.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    } finally {
      await next.close();
      await directory.delete(recursive: true);
    }
  });
}
