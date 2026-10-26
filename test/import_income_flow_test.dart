import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'exposed_accounts_ui_test.dart' as visual;

import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/importing/domain/import_table.dart';
import 'package:so_account/features/importing/domain/import_plan.dart';
import 'package:so_account/features/importing/presentation/import_page.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';

void main() {
  test(
    'source categories follow the resolved row kind, including overrides',
    () {
      final table = ImportTable.fromRows('混合', [
        ['日期', '收支类型', '金额', '类别', '账户'],
        ['2026-10-21', '收入', '10', '稿费', '现金'],
        ['2026-10-21', '支出', '3', '饮食', '现金'],
        ['2026-10-22', '支出', '5', '共用名称', '现金'],
        ['2026-10-22', '收入', '8', '共用名称', '现金'],
      ]);
      final mapping = ImportMapping()..detect(table);
      expect(mapping.categoryValuesFor(table, EntryKind.income), {
        '稿费',
        '共用名称',
      });
      expect(mapping.categoryValuesFor(table, EntryKind.expense), {
        '饮食',
        '共用名称',
      });
      mapping.rowKinds[table.rows.first] = EntryKind.expense;
      expect(mapping.categoryValuesFor(table, EntryKind.income), {'共用名称'});
      expect(
        mapping.categoryValuesFor(table, EntryKind.expense),
        contains('稿费'),
      );
    },
  );

  testWidgets(
    'income source categories can be created and imported independently',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => tester.runAsync(db.close));
      await tester.runAsync(
        () => LedgerRepository(db).saveAccount(
          name: '现金',
          kind: '资金账户',
          channel: '现金',
          currency: 'CNY',
          openingBalance: 0,
        ),
      );
      final table = ImportTable.fromRows('账单', [
        ['日期', '收支类型', '金额', '类别', '账户', '二级分类'],
        ['2026-10-21', '收入', '120', '收入', '现金', '稿费测试'],
        ['2026-10-21', '收入', '120', '收入', '现金', '稿费测试'],
        ['2026-10-21', '支出', '8', '居住', '现金', '不使用'],
      ]);
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await (FontLoader(
        'NotoSansSC',
      )..addFont(rootBundle.load('assets/fonts/NotoSansSC.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final boundary = GlobalKey();
      await visual.mount(
        tester,
        db,
        ImportPage(initialTables: [table]),
        brightness: Brightness.dark,
        boundary: boundary,
      );
      Future<void> settle() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
      }

      await settle();
      await tester.tap(find.text('下一步：账户与分类'));
      await settle();
      final create = find.text('按原名称创建缺失的收入分类');
      await tester.scrollUntilVisible(
        create,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(tester.element(create), alignment: 0.3);
      await tester.pumpAndSettle();
      await visual.capture(tester, boundary, 'import-income-dark-320');
      expect(tester.takeException(), isNull);
      await tester.tap(create);
      await settle();
      final categories = await tester.runAsync(
        () => db.select(db.categories).get(),
      );
      expect(categories!.singleWhere((c) => c.name == '稿费测试').kind, 'income');
      expect(find.text('收入分类内容：居住'), findsNothing);
      await tester.tap(find.text('预览明细'));
      await settle();
      expect(find.text('确认导入 3 条'), findsOneWidget);
      await tester.tap(find.text('确认导入 3 条'));
      await settle();
      final entries = await tester.runAsync(() => db.select(db.entries).get());
      final incomes = entries!.where((e) => e.kind == 'income').toList();
      expect(incomes.length, 2);
      final income = incomes.first;
      expect(income.amount, 12000);
      expect(
        income.categoryId,
        categories.singleWhere((c) => c.name == '稿费测试').id,
      );
      expect(entries.singleWhere((e) => e.kind == 'expense').amount, 800);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );
}
