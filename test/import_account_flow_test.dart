import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/app/providers/providers.dart';
import 'package:so_account/features/importing/domain/import_table.dart';
import 'package:so_account/features/importing/presentation/import_page.dart';
import 'package:so_account/data/database/app_database.dart';

void main() {
  for (final cancel in [false, true]) {
    testWidgets(
      'missing account ${cancel ? 'cancellation preserves import' : 'creation returns to preview without importing'}',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(() => tester.runAsync(db.close));
        await tester.runAsync(() => db.select(db.categories).get());
        final table = ImportTable.fromRows('test', [
          ['日期', '金额', '账户', '分类', '类型', '币种'],
          ['2026-01-01', '12.50', '旅行钱包', '居住', '支出', 'CNY'],
        ]);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [databaseProvider.overrideWithValue(db)],
            child: MaterialApp(home: ImportPage(initialTables: [table])),
          ),
        );
        Future<void> settleData() async {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pumpAndSettle();
        }

        await settleData();
        await tester.scrollUntilVisible(
          find.text('预览明细'),
          500,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('预览明细'));
        await tester.pumpAndSettle();
        final nameField = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '账户名称',
        );
        expect(tester.widget<TextField>(nameField).controller!.text, '旅行钱包');
        if (cancel) {
          await tester.tap(find.byType(BackButton).first);
          await tester.pumpAndSettle();
          expect(find.text('预览明细'), findsOneWidget);
        } else {
          for (final entry in {
            '渠道': '现金',
            '账户类型': '资金账户',
            '币种': 'CNY',
          }.entries) {
            final dropdown = find.byWidgetPredicate(
              (w) =>
                  w is DropdownButtonFormField<String> &&
                  w.decoration.labelText == entry.key,
            );
            await tester.scrollUntilVisible(
              dropdown,
              200,
              scrollable: find.byType(Scrollable).last,
            );
            await tester.tap(dropdown);
            await tester.pumpAndSettle();
            await tester.tap(find.text(entry.value).last);
            await tester.pumpAndSettle();
          }
          final opening = find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == '初始余额',
          );
          await tester.scrollUntilVisible(
            opening,
            200,
            scrollable: find.byType(Scrollable).last,
          );
          expect(tester.widget<TextField>(opening).controller!.text, '');
          await tester.enterText(opening, '100');
          await tester.scrollUntilVisible(
            find.text('保存'),
            200,
            scrollable: find.byType(Scrollable).last,
          );
          await tester.tap(find.text('保存'));
          await settleData();
          expect(find.text('确认导入 1 条'), findsOneWidget);
          final accounts = await tester.runAsync(
            () => db.select(db.accounts).get(),
          );
          expect(accounts!.single.openingBalance, 10000);
          expect(accounts.single.currency, 'CNY');
        }
        expect(
          await tester.runAsync(() => db.select(db.entries).get()),
          isEmpty,
        );
        if (cancel) {
          expect(
            await tester.runAsync(() => db.select(db.accounts).get()),
            isEmpty,
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
      },
    );
  }
}
