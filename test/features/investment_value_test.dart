import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/backup/data/backup_service.dart';
import 'package:so_account/features/backup/domain/backup_codec.dart';
import 'package:so_account/features/inventory/data/inventory_repository.dart';
import 'package:so_account/features/inventory/domain/inventory_sort.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/domain/asset_summary.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';
import 'package:so_account/platform/media/media_store.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  test(
    'schema 10 upgrades keep accounts, products, transactions and cost',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'valuation_migration_',
      );
      final file = File('${root.path}/old.db');
      var db = AppDatabase(NativeDatabase(file));
      try {
        final repo = LedgerRepository(db);
        final id = await repo.saveAccount(
          name: '旧理财账户',
          kind: '投资理财',
          channel: '基金',
          currency: 'CNY',
          openingBalance: 10000,
        );
        final cash = await repo.saveAccount(
          name: '旧现金账户',
          kind: '资金账户',
          channel: '现金',
          currency: 'CNY',
          openingBalance: 50000,
        );
        final product = await repo.saveInvestmentProduct(
          accountId: id,
          name: '旧产品',
          kind: '基金',
        );
        await repo.saveEntry(
          kind: EntryKind.invest,
          amount: 5000,
          accountId: cash,
          targetAccountId: id,
          investmentProductId: product,
          date: '2026-11-01',
        );
        final balances = await repo.balances();
        await db.customStatement(
          'ALTER TABLE accounts DROP COLUMN current_value',
        );
        await db.customStatement('ALTER TABLE accounts DROP COLUMN valued_at');
        await db.customStatement('PRAGMA user_version=10');
        await db.close();
        db = AppDatabase(NativeDatabase(file));
        final accounts = await db.select(db.accounts).get();
        expect(
          accounts.every((a) => a.currentValue == null && a.valuedAt == null),
          isTrue,
        );
        expect(await LedgerRepository(db).balances(), balances);
        expect(
          (await db.select(db.investmentProducts).get()).single.id,
          product,
        );
        expect(
          (await db.select(db.entries).get()).single.investmentProductId,
          product,
        );
        expect(
          await db.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
        expect(
          (await db.customSelect('PRAGMA user_version').getSingle())
              .data
              .values
              .single,
          11,
        );
      } finally {
        await db.close();
        await root.delete(recursive: true);
      }
    },
  );
  test('manual value and sort survive restart and backup without changing cost or income', () async {
    final root = await Directory.systemTemp.createTemp('investment_value_');
    final file = File('${root.path}/ledger.db');
    var db = AppDatabase(NativeDatabase(file));
    try {
      var repo = LedgerRepository(db);
      final id = await repo.saveAccount(
        name: '合成理财',
        kind: '投资理财',
        channel: '基金',
        currency: 'CNY',
        openingBalance: 10000,
      );
      final cash = await repo.saveAccount(
        name: '合成现金',
        kind: '资金账户',
        channel: '现金',
        currency: 'CNY',
        openingBalance: 50000,
      );
      final product = await repo.saveInvestmentProduct(
        accountId: id,
        name: '合成产品',
        kind: '基金',
      );
      await repo.saveEntry(
        kind: EntryKind.invest,
        amount: 5000,
        accountId: cash,
        targetAccountId: id,
        investmentProductId: product,
        date: '2026-11-01',
      );
      await repo.updateInvestmentValue(
        accountId: id,
        expectedCurrency: 'CNY',
        currentValue: 18675,
      );
      await InventoryRepository(db).saveSort('price');
      final before = await repo.watchBalances().first;
      expect(before[id], 15000);
      final stamp = (await db.select(db.accounts).get())
          .singleWhere((a) => a.id == id)
          .valuedAt;
      await db.close();
      db = AppDatabase(NativeDatabase(file));
      repo = LedgerRepository(db);
      var account = (await db.select(db.accounts).get()).singleWhere(
        (a) => a.id == id,
      );
      expect(account.currentValue, 18675);
      expect(account.valuedAt, stamp);
      expect(
        (await db.select(db.preferences).get())
            .singleWhere((p) => p.key == inventorySortKey)
            .value,
        'price',
      );
      await repo.saveAccount(
        id: id,
        name: '合成理财改名',
        kind: account.kind,
        channel: account.channel,
        currency: account.currency,
        openingBalance: account.openingBalance,
      );
      expect(
        (await db.select(db.accounts).get())
            .singleWhere((a) => a.id == id)
            .currentValue,
        18675,
      );
      final service = BackupService(db, MediaStore(root));
      final backup = await service.export();
      await repo.updateInvestmentValue(
        accountId: id,
        expectedCurrency: 'CNY',
        currentValue: 0,
      );
      await InventoryRepository(db).saveSort('name');
      await service.restore(backup);
      account = (await db.select(db.accounts).get()).singleWhere(
        (a) => a.id == id,
      );
      expect(account.currentValue, 18675);
      expect(account.valuedAt, stamp);
      expect(await repo.watchBalances().first, before);
      expect((await db.select(db.entries).get()).length, 1);
      expect(await db.select(db.balanceAdjustments).get(), isEmpty);
      expect(
        AssetSummary.calculate(await db.select(db.accounts).get(), before).net,
        60000,
      );
      expect(
        (await db.select(db.preferences).get())
            .singleWhere((p) => p.key == inventorySortKey)
            .value,
        'price',
      );

      // Reject malformed snapshots atomically, including invalid preferences.
      for (final mutation in ['amount', 'timestamp', 'kind', 'sort']) {
        final files = decodeBackup(backup);
        final json = jsonDecode(
          utf8.decode(files['data.json']!),
        ) as Map<String, dynamic>;
        final row = (json['accounts'] as List).singleWhere(
          (a) => a['id'] == id,
        );
        if (mutation == 'amount') row['currentValue'] = -1;
        if (mutation == 'timestamp') row['valuedAt'] = null;
        if (mutation == 'kind') row['kind'] = '资金账户';
        if (mutation == 'sort') {
          (json['preferences'] as List).singleWhere(
            (p) => p['key'] == inventorySortKey,
          )['value'] = 'bad';
        }
        files['data.json'] = Uint8List.fromList(utf8.encode(jsonEncode(json)));
        await expectLater(
          service.restore(encodeBackup(files)),
          throwsFormatException,
        );
        expect(
          (await db.select(db.accounts).get())
              .singleWhere((a) => a.id == id)
              .currentValue,
          18675,
        );
      }
      // Older logical backups omit new nullable fields and the sort preference.
      final files = decodeBackup(backup);
      final json =
          jsonDecode(utf8.decode(files['data.json']!)) as Map<String, dynamic>;
      for (final row in json['accounts']) {
        row.remove('currentValue');
        row.remove('valuedAt');
      }
      (json['preferences'] as List).removeWhere(
        (p) => p['key'] == inventorySortKey,
      );
      files['data.json'] = Uint8List.fromList(utf8.encode(jsonEncode(json)));
      await service.restore(encodeBackup(files));
      expect(
        (await db.select(db.accounts).get()).every(
          (a) => a.currentValue == null && a.valuedAt == null,
        ),
        isTrue,
      );
    } finally {
      await db.close();
      await root.delete(recursive: true);
    }
  });

  test(
    'value updates validate type, archive, currency, limits and clear',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        final repo = LedgerRepository(db);
        final id = await repo.saveAccount(
          name: '测试理财',
          kind: '投资理财',
          channel: '股票',
          currency: 'JPY',
          openingBalance: 100,
        );
        final cash = await repo.saveAccount(
          name: '测试现金',
          kind: '资金账户',
          channel: '现金',
          currency: 'JPY',
          openingBalance: 0,
        );
        for (final input in [
          (id, 'JPY', -1),
          (id, 'JPY', 1000000000000),
          (id, 'USD', 1),
          (cash, 'JPY', 1),
          ('missing', 'JPY', 1),
        ]) {
          await expectLater(
            repo.updateInvestmentValue(
              accountId: input.$1,
              expectedCurrency: input.$2,
              currentValue: input.$3,
            ),
            throwsFormatException,
          );
        }
        await repo.updateInvestmentValue(
          accountId: id,
          expectedCurrency: 'JPY',
          currentValue: 0,
        );
        expect(
          (await db.select(db.accounts).get())
              .singleWhere((a) => a.id == id)
              .currentValue,
          0,
        );
        await expectLater(
          repo.saveAccount(
            id: id,
            name: '测试理财',
            kind: '资金账户',
            channel: '现金',
            currency: 'JPY',
            openingBalance: 100,
          ),
          throwsFormatException,
        );
        await repo.archiveAccount(id);
        await expectLater(
          repo.updateInvestmentValue(
            accountId: id,
            expectedCurrency: 'JPY',
            currentValue: 1,
          ),
          throwsFormatException,
        );
        await repo.restoreAccount(id);
        await repo.updateInvestmentValue(
          accountId: id,
          expectedCurrency: 'JPY',
          currentValue: null,
        );
        final cleared = (await db.select(db.accounts).get()).singleWhere(
          (a) => a.id == id,
        );
        expect(cleared.currentValue, isNull);
        expect(cleared.valuedAt, isNull);
        await expectLater(
          InventoryRepository(db).saveSort('bad'),
          throwsFormatException,
        );
      } finally {
        await db.close();
      }
    },
  );
}
