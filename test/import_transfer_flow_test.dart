import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/app/providers/providers.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/importing/domain/import_table.dart';
import 'package:so_account/features/importing/presentation/import_page.dart';
import 'package:so_account/platform/files/file_delivery.dart';

class SavedTemplate extends FileDelivery {
  Uint8List? bytes;
  @override
  Future<bool> save(String name, Uint8List bytes) async {
    this.bytes = bytes;
    return true;
  }
}

void main() {
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  for (final kind in ['转账', '转帐', '还款', '借出']) {
    testWidgets(
      '$kind import is ignored without creating funds or debt accounts',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(() => tester.runAsync(db.close));
        final table = ImportTable.fromRows('非收支', [
          ['日期', '类型', '金额', '账户', '转出账户', '转入账户'],
          ['2026-10-23', kind, '10', '不应创建', '源账户', '目标账户'],
        ]);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [databaseProvider.overrideWithValue(db)],
            child: MaterialApp(home: ImportPage(initialTables: [table])),
          ),
        );
        await settle(tester);
        await tester.tap(find.text('下一步：账户与分类'));
        await settle(tester);
        expect(find.text('默认账户'), findsNothing);
        expect(find.textContaining('还款含义'), findsNothing);
        await tester.tap(find.text('预览明细'));
        await settle(tester);
        expect(find.text('忽略 1 条'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, '确认导入 0 条'),
              )
              .onPressed,
          isNull,
        );
        expect(
          await tester.runAsync(() => db.select(db.accounts).get()),
          isEmpty,
        );
        expect(
          await tester.runAsync(() => db.select(db.entries).get()),
          isEmpty,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
      },
    );
  }
  testWidgets('only the income/expense template is offered', (tester) async {
    final delivery = SavedTemplate();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          snapshotProvider.overrideWith(
            (ref) => Stream.value(AppSnapshot([], [], [], [], [], [], [])),
          ),
          fileDeliveryProvider.overrideWithValue(delivery),
        ],
        child: const MaterialApp(home: ImportPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('保存转账 CSV 模板'), findsNothing);
    await tester.tap(find.text('保存收支 CSV 模板'));
    await tester.pumpAndSettle();
    final table = readImportTables('模板.csv', delivery.bytes!).single;
    expect(table.headers.length, 23);
    expect(table.rows.map((r) => r[1]), ['支出', '收入']);
  });
}
