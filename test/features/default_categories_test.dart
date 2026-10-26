import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/ledger/domain/default_categories.dart';

void main() {
  test(
    'additional top-level defaults upgrade once and respect later deletions',
    () async {
      final dir = await Directory.systemTemp.createTemp('so_categories_');
      final file = File('${dir.path}/ledger.db');
      var db = AppDatabase(NativeDatabase(file));
      try {
        final defaults = await db.select(db.categories).get();
        expect(
          defaults.map((c) => c.name),
          containsAll(additionalExpenseDefaults),
        );
        expect(
          defaults.map((c) => c.name),
          containsAll(additionalIncomeDefaults),
        );
        // Simulate the previous version's data without the new seed marker.
        await (db.delete(
          db.preferences,
        )..where((p) => p.key.equals('category_defaults_20261025'))).go();
        await (db.delete(
          db.categories,
        )..where((c) => c.name.equals('宠物'))).go();
        await db
            .into(db.categories)
            .insert(
              CategoriesCompanion.insert(
                id: 'custom',
                name: '自定义用途',
                kind: 'expense',
              ),
            );
        await db.close();
        db = AppDatabase(NativeDatabase(file));
        var rows = await db.select(db.categories).get();
        expect(rows.where((c) => c.name == '宠物'), hasLength(1));
        expect(rows.where((c) => c.id == 'custom'), hasLength(1));
        await (db.delete(
          db.categories,
        )..where((c) => c.name.equals('宠物'))).go();
        await db.close();
        db = AppDatabase(NativeDatabase(file));
        rows = await db.select(db.categories).get();
        expect(rows.where((c) => c.name == '宠物'), isEmpty);
        expect(rows.where((c) => c.id == 'custom'), hasLength(1));
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
