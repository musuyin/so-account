import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/ledger/domain/default_categories.dart';
import 'package:so_account/features/ledger/domain/asset_summary.dart';

import '../../generated/schema_v1.dart';

void main() {
  test(
    'v1 migration retains historical category IDs and adds requested defaults',
    () async {
      final dir = await Directory.systemTemp.createTemp('so_migrate_');
      final file = File('${dir.path}/v1.db');
      final old = DatabaseAtV1(NativeDatabase(file));
      await old.customStatement(
        "INSERT INTO accounts VALUES ('cash','旧账户','资金账户','现金','CNY',10000)",
      );
      await old.customStatement(
        "INSERT INTO categories VALUES ('expense-0','饮食','expense')",
      );
      await old.customStatement(
        "INSERT INTO categories VALUES ('income-0','自定义改名','income')",
      );
      await old.customStatement(
        "INSERT INTO entries VALUES ('old','expense',100,'cash',NULL,'expense-0',NULL,'2026-10-01','',0,0)",
      );
      await old.customStatement(
        "INSERT INTO items (id,name,category,price,currency,purchased_on,note,created_at,updated_at) VALUES ('item','旧物品','数码',5000,'CNY','2026-10-01','',0,0)",
      );
      await old.customStatement(
        "INSERT INTO purchase_links VALUES ('item','old')",
      );
      await old.close();
      final next = AppDatabase(NativeDatabase(file));
      try {
        expect((await next.select(next.accounts).get()).single.avatar, '');
        expect(
          (await next.select(next.entries).get()).single.categoryId,
          'expense-0',
        );
        final item = (await next.select(next.items).get()).single;
        expect(item.price, 5000);
        expect(item.useType, 'durable');
        expect(item.status, 'active');
        expect(item.archivedOn, isNull);
        expect(
          (await next.select(next.purchaseLinks).get()).single.entryId,
          'old',
        );
        final categories = await next.select(next.categories).get();
        expect(
          categories.map((c) => c.name),
          containsAll([
            ...expenseDefaults.map((c) => c.name),
            ...incomeDefaults.map((c) => c.name),
            '饮食',
            '自定义改名',
          ]),
        );
        expect(
          await next.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      } finally {
        await next.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test('net assets include receivables and liabilities without counting borrowing as income', () {
    final summary = AssetSummary.calculate(
      [10000, -2000],
      receivable: 3000,
      payable: 4000,
    );
    expect(summary.assets, 13000);
    expect(summary.liabilities, 6000);
    expect(summary.net, 7000);
  });
}
