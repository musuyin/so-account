import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/inventory/data/inventory_repository.dart';
import 'package:so_account/features/inventory/domain/item_categories.dart';

void main() {
  test('quantities, multi-category renames and usage states persist', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final repo = InventoryRepository(db);
    try {
      await repo.save(
        name: '茶',
        category: encodeItemTags(['食物', '日用品']),
        currency: 'CNY',
        useType: 'consumable',
        status: 'unused',
        quantity: '500.5',
        unit: 'g',
      );
      await repo.saveCategory('食品', previous: '食物');
      final item = (await db.select(db.items).get()).single;
      expect(itemTags(item.category), ['食品', '日用品']);
      expect(item.quantity, '500.5');
      expect(item.unit, 'g');
      expect(item.status, 'unused');
      await expectLater(repo.deleteCategory('食品'), throwsFormatException);
      await repo.saveCategory('自定义');
      await repo.deleteCategory('自定义');
      for (final value in ['0', '-1', 'NaN', '1.2345678']) {
        await expectLater(
          repo.save(
            name: '错误',
            category: '食物',
            currency: 'CNY',
            useType: 'consumable',
            quantity: value,
          ),
          throwsFormatException,
        );
      }
      await expectLater(
        repo.save(name: '错误', category: '食物', currency: 'CNY', quantity: '1'),
        throwsFormatException,
      );
      await expectLater(
        repo.save(
          name: '错误',
          category: '食物',
          currency: 'CNY',
          status: 'completed',
        ),
        throwsFormatException,
      );
    } finally {
      await db.close();
    }
  });

  test(
    'v2 migration maps retired and depleted without losing archive dates',
    () async {
      final dir = await Directory.systemTemp.createTemp('so_v2_');
      final file = File('${dir.path}/data.db');
      final old = NativeDatabase(file);
      await old.ensureOpen(_Version2());
      await old.runCustom(
        "CREATE TABLE accounts (id TEXT PRIMARY KEY, name TEXT NOT NULL, kind TEXT NOT NULL, channel TEXT NOT NULL, currency TEXT NOT NULL, avatar TEXT NOT NULL DEFAULT '', opening_balance INTEGER NOT NULL DEFAULT 0)",
        [],
      );
      await old.runCustom(
        "CREATE TABLE entries (id TEXT PRIMARY KEY, kind TEXT NOT NULL, amount INTEGER NOT NULL, account_id TEXT NOT NULL, target_account_id TEXT, category_id TEXT, debt_id TEXT, date TEXT NOT NULL, note TEXT NOT NULL DEFAULT '', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)",
        [],
      );
      await old.runCustom(
        "CREATE TABLE items (id TEXT PRIMARY KEY, name TEXT NOT NULL, category TEXT NOT NULL DEFAULT '未分类', use_type TEXT NOT NULL DEFAULT 'durable', status TEXT NOT NULL DEFAULT 'active', archived_on TEXT, price INTEGER, currency TEXT NOT NULL, purchased_on TEXT, note TEXT NOT NULL DEFAULT '', photo TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)",
        [],
      );
      for (final status in ['retired', 'depleted', 'active']) {
        await old.runCustom(
          "INSERT INTO items (id,name,status,archived_on,currency,created_at,updated_at) VALUES (?,?,?,?,'CNY',0,0)",
          [status, status, status, status == 'active' ? null : '2026-10-01'],
        );
      }
      await old.runCustom(
        'CREATE TABLE preferences (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        [],
      );
      await old.runCustom(
        'CREATE TABLE categories (id TEXT PRIMARY KEY, name TEXT NOT NULL, kind TEXT NOT NULL)',
        [],
      );
      await old.runCustom('PRAGMA user_version = 2', []);
      await old.close();
      final next = AppDatabase(NativeDatabase(file));
      try {
        final items = await next.select(next.items).get();
        expect(items.where((i) => i.status == 'completed').length, 2);
        expect(
          items.firstWhere((i) => i.id == 'retired').archivedOn,
          '2026-10-01',
        );
        expect(
          items.every((i) => i.quantity == null && i.unit == null),
          isTrue,
        );
      } finally {
        await next.close();
        await dir.delete(recursive: true);
      }
    },
  );
}

class _Version2 extends QueryExecutorUser {
  @override
  int get schemaVersion => 2;
  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}
