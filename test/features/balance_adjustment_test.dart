import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';
import 'package:so_account/features/statistics/data/statistics_repository.dart';
import 'package:so_account/features/statistics/domain/report_range.dart';
import 'package:so_account/features/backup/data/backup_service.dart';
import 'package:so_account/features/backup/domain/backup_codec.dart';
import 'package:so_account/platform/media/media_store.dart';

void main() {
  late AppDatabase db;
  late LedgerRepository repo;
  late String cash;
  final at = DateTime(2026, 10, 22, 12);
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = LedgerRepository(db);
    cash = await repo.saveAccount(
      name: '钱包',
      kind: '资金账户',
      channel: '现金',
      currency: 'CNY',
      openingBalance: 10000,
    );
  });
  tearDown(() => db.close());
  Future<FinanceReport> report() =>
      StatisticsRepository(db)
          .load(ReportRange.at(ReportPeriod.month, at), 'CNY');
  test('adjustment keeps ledger, opening balance and budget intact; assets change from its date', () async {
    final categories = await db.select(db.categories).get();
    await repo.saveEntry(
      kind: EntryKind.income,
      amount: 200,
      accountId: cash,
      date: '2026-10-01',
      categoryId: categories.firstWhere((c) => c.kind == 'income').id,
    );
    await repo.saveEntry(
      kind: EntryKind.expense,
      amount: 500,
      accountId: cash,
      date: '2026-10-02',
      categoryId: categories.firstWhere((c) => c.kind == 'expense').id,
    );
    await repo.setBudget('2026-10', 'CNY', 1000);
    await repo.adjustBalance(
      accountId: cash,
      desiredBalance: 1000,
      expectedBalance: 9700,
      reason: '导入后核对',
      at: at,
    );
    expect((await repo.balances())[cash], 1000);
    expect((await db.select(db.entries).get()).length, 2);
    expect((await db.select(db.accounts).get()).single.openingBalance, 10000);
    expect((await db.select(db.budgets).get()).single.amount, 1000);
    final result = await report();
    expect(result.income, 200);
    expect(result.expense, 500);
    expect(
      result.points.singleWhere((p) => p.label == '2026-10-21').netAssets,
      9700,
    );
    expect(
      result.points.singleWhere((p) => p.label == '2026-10-22').netAssets,
      1000,
    );
    final adjustment = (await db.select(db.balanceAdjustments).get()).single;
    expect(adjustment.delta, -8700);
    expect(adjustment.reason, '导入后核对');
  });
  test('multiple corrections never multiply ledger sums and allow zero or negative balances', () async {
    final category = (await db.select(db.categories).get()).firstWhere(
      (c) => c.kind == 'expense',
    );
    for (final amount in [100, 200]) {
      await repo.saveEntry(
        kind: EntryKind.expense,
        amount: amount,
        accountId: cash,
        date: '2026-10-01',
        categoryId: category.id,
      );
    }
    var before = 9700;
    for (final desired in [10000, 0, -350]) {
      await repo.adjustBalance(
        accountId: cash,
        desiredBalance: desired,
        expectedBalance: before,
        at: at,
      );
      expect((await repo.balances())[cash], desired);
      before = desired;
    }
    expect((await db.select(db.entries).get()).length, 2);
    expect((await db.select(db.balanceAdjustments).get()).length, 3);
    expect((await report()).expense, 300);
    await repo.adjustBalance(
      accountId: cash,
      desiredBalance: -350,
      expectedBalance: -350,
      at: at,
    );
    expect((await db.select(db.balanceAdjustments).get()).length, 3);
  });
  test('stale expected balance, invalid amounts and deleted account never change audit or transactions', () async {
    await repo.adjustBalance(
      accountId: cash,
      desiredBalance: 12000,
      expectedBalance: 10000,
      at: at,
    );
    await expectLater(
      repo.adjustBalance(
        accountId: cash,
        desiredBalance: 1,
        expectedBalance: 10000,
      ),
      throwsFormatException,
    );
    await expectLater(
      repo.adjustBalance(
        accountId: cash,
        desiredBalance: 1000000000000,
        expectedBalance: 12000,
      ),
      throwsFormatException,
    );
    await expectLater(
      repo.adjustBalance(
        accountId: 'missing',
        desiredBalance: 1,
        expectedBalance: 0,
      ),
      throwsFormatException,
    );
    expect((await repo.balances())[cash], 12000);
    expect((await db.select(db.balanceAdjustments).get()).length, 1);
    expect(await db.select(db.entries).get(), isEmpty);
    await expectLater(
      repo.saveAccount(
        id: cash,
        name: '钱包',
        kind: '资金账户',
        channel: '现金',
        currency: 'USD',
        openingBalance: 10000,
      ),
      throwsFormatException,
    );
  });
  test(
    'payable corrections reduce liabilities without generating income',
    () async {
      final payable = await repo.saveAccount(
        name: '小林',
        kind: '债务',
        channel: '应付款',
        currency: 'CNY',
        openingBalance: 2000,
      );
      await repo.adjustBalance(
        accountId: payable,
        desiredBalance: 500,
        expectedBalance: 2000,
        at: at,
      );
      final result = await report();
      expect(result.income, 0);
      expect(result.expense, 0);
      expect(
        result.points.singleWhere((p) => p.label == '2026-10-21').netAssets,
        8000,
      );
      expect(
        result.points.singleWhere((p) => p.label == '2026-10-22').netAssets,
        9500,
      );
    },
  );
  test('backup preserves corrections and exact investment price; corrupt audit is rejected atomically', () async {
    final root = await Directory.systemTemp.createTemp('so_balance_backup_');
    try {
      final investment = await repo.saveAccount(
        name: '基金',
        kind: '投资理财',
        channel: '基金',
        currency: 'CNY',
        openingBalance: 2000,
        unitPrice: '0.12345678',
      );
      await repo.adjustBalance(
        accountId: investment,
        desiredBalance: 1800,
        expectedBalance: 2000,
        at: at,
      );
      final backup = BackupService(db, MediaStore(root));
      final bytes = await backup.export();
      await backup.restore(bytes);
      expect((await repo.balances())[investment], 1800);
      expect(
        (await db.select(db.accounts).get())
            .singleWhere((a) => a.id == investment)
            .unitPrice,
        '0.12345678',
      );
      final files = decodeBackup(bytes);
      final json =
          jsonDecode(utf8.decode(files['data.json']!)) as Map<String, dynamic>;
      (json['adjustments'] as List).single['delta'] = 1;
      files['data.json'] = Uint8List.fromList(utf8.encode(jsonEncode(json)));
      await expectLater(
        backup.restore(encodeBackup(files)),
        throwsFormatException,
      );
      expect((await repo.balances())[investment], 1800);
      expect(await db.select(db.entries).get(), isEmpty);
    } finally {
      await root.delete(recursive: true);
    }
  });
  test(
    'v5 database adds empty adjustment store and preserves existing entries',
    () async {
      final root = await Directory.systemTemp.createTemp('so_v5_');
      final file = File('${root.path}/old.db');
      final old = AppDatabase(NativeDatabase(file));
      final ledger = LedgerRepository(old);
      final id = await ledger.saveAccount(
        name: '旧钱包',
        kind: '资金账户',
        channel: '现金',
        currency: 'CNY',
        openingBalance: 5000,
      );
      await old.customStatement('DROP TABLE balance_adjustments');
      await old.customStatement('DROP TABLE goal_contributions');
      await old.customStatement('DROP TABLE wish_goals');
      await old.customStatement('ALTER TABLE accounts DROP COLUMN bank');
      await old.customStatement('ALTER TABLE accounts DROP COLUMN is_archived');
      await old.customStatement('PRAGMA user_version=5');
      await old.close();
      final next = AppDatabase(NativeDatabase(file));
      try {
        expect((await LedgerRepository(next).balances())[id], 5000);
        expect(await next.select(next.balanceAdjustments).get(), isEmpty);
        expect(
          await next.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      } finally {
        await next.close();
        await root.delete(recursive: true);
      }
    },
  );
}
