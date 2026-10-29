import 'package:drift/native.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/app/providers/providers.dart';
import 'package:so_account/app/theme/app_theme.dart';
import 'package:so_account/core/appearance.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/importing/domain/import_table.dart';
import 'package:so_account/features/importing/presentation/import_page.dart';
import 'package:so_account/features/inventory/presentation/item_form.dart';
import 'package:so_account/features/inventory/domain/item_categories.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';

void main() {
  testWidgets('import previews row errors and only commits selected entries', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await (FontLoader(
      'NotoSansSC',
    )..addFont(rootBundle.load('assets/fonts/NotoSansSC.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final boundary = GlobalKey();
    Future<void> screenshot(String name) => tester.runAsync(() async {
      final picture =
          await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final data = await picture.toByteData(format: ui.ImageByteFormat.png);
      await Directory('.tooling/screenshots').create(recursive: true);
      await File('.tooling/screenshots/$name.png')
          .writeAsBytes(data!.buffer.asUint8List());
      picture.dispose();
    });
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
    final accounts = await tester.runAsync(() => db.select(db.accounts).get());
    final categories = await tester.runAsync(
      () => db.select(db.categories).get(),
    );
    final data = AppSnapshot(accounts!, categories!, [], [], [], [], []);
    final table = ImportTable.fromRows('测试', [
      ['日期', '金额', '账户', '分类', '类型'],
      ['2026-01-01', '12.50', '现金', '居住', '支出'],
      ['错误日期', '3', '现金', '居住', '支出'],
    ]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          snapshotProvider.overrideWith((ref) => Stream.value(data)),
          databaseProvider.overrideWithValue(db),
        ],
        child: RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            theme: appTheme(Brightness.light, palette: AppPalette.cucumber),
            home: ImportPage(initialTables: [table]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await screenshot('import-columns');
    await tester.tap(find.text('下一步：账户与分类'));
    await tester.pumpAndSettle();
    await screenshot('import-mapping');
    await tester.scrollUntilVisible(find.text('预览明细'), 500);
    await tester.tap(find.text('预览明细'));
    await tester.pumpAndSettle();
    expect(find.text('确认导入 1 条'), findsOneWidget);
    expect(find.textContaining('错误 1 条'), findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pump();
    expect(tester.getBottomRight(find.text('确认导入 1 条')).dy, lessThan(540));
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    await screenshot('import-review');
    await tester.tap(find.widgetWithText(ChoiceChip, '错误'));
    await tester.pumpAndSettle();
    expect(find.text('确认导入 1 条'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '重复'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, '已忽略'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('没有匹配的明细'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('确认导入 1 条'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '全部'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认导入 1 条'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
    expect(find.text('已导入 1 条明细'), findsOneWidget);
    final entries = await tester.runAsync(() => db.select(db.entries).get());
    expect(entries!.single.amount, 1250);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets(
    'item categories select immediately and consumption fields are optional',
    (tester) async {
      final data = AppSnapshot([], [], [], [], [], [], []);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            snapshotProvider.overrideWith((ref) => Stream.value(data)),
          ],
          child: const MaterialApp(
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: [Locale('zh', 'CN')],
            locale: Locale('zh', 'CN'),
            home: ItemForm(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final name in ['日用品', '食物']) {
        await tester.tap(find.text(name));
        await tester.pump();
        expect(
          tester
              .widget<FilterChip>(
                find.ancestor(
                  of: find.text(name),
                  matching: find.byType(FilterChip),
                ),
              )
              .selected,
          isTrue,
        );
      }
      await tester.tap(find.text('长期使用物'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('消耗品').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('数量 / 容量（可留空）'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('单位（可留空）'), findsOneWidget);
      expect(itemStatuses.values, ['未使用', '使用中', '使用完']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
