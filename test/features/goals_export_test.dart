import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/core/time/business_date.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/goals/data/goals_repository.dart';
import 'package:so_account/features/goals/data/goals_export.dart';
import 'package:so_account/features/importing/domain/import_table.dart';

void main() {
  test('goal CSV retains currencies, overfunding, archived records, multiline and formula-safe names', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      final repo = GoalsRepository(db);
      final id = await repo.save(
        name: '=旅行,计划',
        kind: 'saving',
        currency: 'CNY',
        target: 10000,
        initialSaved: 12000,
        note: '第一行\n第二行',
      );
      await repo.contribute(
        goalId: id,
        amount: -1000,
        date: dateKey(DateTime.now()),
        note: '取出,修正',
      );
      await repo.setStatus(id, 'archived');
      await repo.save(
        name: '相机',
        kind: 'wish',
        currency: 'JPY',
        target: 100000,
        initialSaved: 30000,
      );
      final csv = await GoalsExport(db).create();
      final table = readImportTables(
        'goals.csv',
        Uint8List.fromList(utf8.encode(csv)),
      ).single;
      expect(table.rows.length, 2);
      final cny = table.rows.singleWhere((r) => r[3] == 'CNY');
      expect(cny[1], "'=旅行,计划");
      expect(cny[4], '100.00');
      expect(cny[5], '110.00');
      expect(cny[6], '0.00');
      expect(cny[9], '已归档');
      expect(cny[10], '第一行\n第二行');
      expect(table.rows.singleWhere((r) => r[3] == 'JPY')[4], '100000');
      final details = readImportTables(
        'details.csv',
        Uint8List.fromList(
          utf8.encode(await GoalsExport(db).create(details: true)),
        ),
      ).single;
      expect(details.rows.length, 3);
      final withdrawal = details.rows.singleWhere((r) => r[6] == '取出');
      expect(withdrawal[7], '10.00');
      expect(withdrawal[8], '取出,修正');
      expect(await db.select(db.entries).get(), isEmpty);
    } finally {
      await db.close();
    }
  });
}
