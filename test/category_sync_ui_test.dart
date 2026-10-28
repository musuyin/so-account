import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/app/category_reordering.dart';
import 'package:so_account/app/providers/providers.dart';
import 'package:so_account/app/theme/app_theme.dart';
import 'package:so_account/app/widgets.dart';
import 'package:so_account/features/inventory/data/inventory_repository.dart';
import 'package:so_account/features/inventory/presentation/item_form.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/presentation/category_icon_picker.dart';
import 'package:so_account/features/ledger/presentation/category_icons.dart';
import 'package:so_account/features/ledger/presentation/home_page.dart';
import 'package:so_account/features/settings/presentation/categories_page.dart';
import 'package:so_account/features/settings/presentation/item_categories_page.dart';

import 'entry_purchase_flow_test.dart' as flow;

ReorderableCategoryGrid entryGrid(WidgetTester t) =>
    t.widget<ReorderableCategoryGrid>(
      find.byType(ReorderableCategoryGrid).first,
    );

Future<void> move(WidgetTester t, Finder from, Finder to) async {
  final end = t.getCenter(to);
  final gesture = await t.startGesture(t.getCenter(from));
  await t.pump(const Duration(milliseconds: 600));
  await gesture.moveTo(end);
  await t.pump(const Duration(milliseconds: 200));
  await gesture.up();
  await flow.settle(t);
}

void main() {
  testWidgets(
    'entry and management sync in both directions without losing selection, amount, note or purchase draft',
    (t) async {
      final db = await flow.database(t);
      await flow.open(t, db);
      final ids = entryGrid(t).ids;
      final selected = ids[1];
      final selection = find.byKey(ValueKey('entry-category-$selected'));
      await t.tap(selection);
      await flow.enterAmount(t);
      await t.tap(find.byKey(const ValueKey('entry-note')));
      await t.pumpAndSettle();
      await t.enterText(flow.field('备注'), '合成备注草稿');
      await t.tap(find.text('确认备注'));
      await t.pumpAndSettle();
      await t.tap(flow.itemSwitch);
      await t.pumpAndSettle();
      await t.enterText(flow.field('物品名称'), '合成物品草稿');
      await t.tap(find.widgetWithText(ChoiceChip, '日用品'));
      await t.tap(find.text('确认记物'));
      await t.pumpAndSettle();
      await move(
        t,
        find.byKey(ValueKey('entry-category-${ids.first}')),
        selection,
      );
      expect(entryGrid(t).ids.first, selected);
      // Management receives the grid's persisted order.
      final context = t.element(find.byType(ReorderableCategoryGrid).first);
      openForm(context, const CategoriesPage());
      await flow.settle(t);
      var management = t.widget<CategoryManagementList>(
        find.byType(CategoryManagementList),
      );
      expect(management.groups.first.ids.first, selected);
      await t.runAsync(() => management.onReorder('expense', ids));
      await flow.settle(t);
      Navigator.pop(t.element(find.byType(CategoriesPage)));
      await flow.settle(t);
      expect(entryGrid(t).ids, ids);
      expect(find.text('合成备注草稿'), findsOneWidget);
      await t.tap(flow.itemSwitch);
      await t.pumpAndSettle();
      expect(
        t.widget<TextField>(flow.field('物品名称')).controller!.text,
        '合成物品草稿',
      );
      final itemGrid = t
          .widgetList<ReorderableCategoryGrid>(
            find.byType(ReorderableCategoryGrid),
          )
          .last;
      final reversed = itemGrid.ids.reversed.toList();
      await t.runAsync(
        () => InventoryRepository(db).reorderCategories(reversed),
      );
      await flow.settle(t);
      final updated = t
          .widgetList<ReorderableCategoryGrid>(
            find.byType(ReorderableCategoryGrid),
          )
          .last;
      expect(updated.ids, reversed);
      await flow.showField(t, find.widgetWithText(ChoiceChip, '未分类'));
      await move(
        t,
        find.widgetWithText(ChoiceChip, '未分类'),
        find.widgetWithText(ChoiceChip, '其他'),
      );
      final afterDrag = t
          .widgetList<ReorderableCategoryGrid>(
            find.byType(ReorderableCategoryGrid),
          )
          .last;
      expect(afterDrag.ids.first, '其他');
      expect(
        t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '日用品')).selected,
        isTrue,
      );
      expect(
        t.widget<TextField>(flow.field('物品名称')).controller!.text,
        '合成物品草稿',
      );
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      await t.tap(find.text('保存'));
      await flow.settle(t);
      final entry = (await t.runAsync(() => db.select(db.entries).get()))!
          .single;
      expect(entry.categoryId, selected);
      expect(entry.amount, 700);
      expect(entry.note, '合成备注草稿');
      expect(
        (await t.runAsync(() => db.select(db.items).get()))!.single.name,
        '合成物品草稿',
      );
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets('canceling entry retains global category order', (t) async {
    final db = await flow.database(t);
    await flow.open(t, db);
    final ids = entryGrid(t).ids;
    await move(
      t,
      find.byKey(ValueKey('entry-category-${ids.first}')),
      find.byKey(ValueKey('entry-category-${ids[2]}')),
    );
    final reordered = entryGrid(t).ids;
    Navigator.pop(t.element(find.byType(ReorderableCategoryGrid).first));
    await flow.settle(t);
    expect(await t.runAsync(() => db.select(db.entries).get()), isEmpty);
    final categories = await t.runAsync(
      () => LedgerRepository(db).watchCategories().first,
    );
    expect(
      categories!.where((c) => c.kind == 'expense').map((c) => c.id),
      reordered,
    );
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(milliseconds: 1));
  });

  testWidgets(
    'category forms pick explicit icons, cancel safely and retain them after rename',
    (t) async {
      final db = await flow.database(t);
      await t.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Column(
                  children: [
                    TextButton(
                      onPressed: () => openForm(context, const CategoryForm()),
                      child: const Text('收支'),
                    ),
                    TextButton(
                      onPressed: () =>
                          openForm(context, const ItemCategoryForm()),
                      child: const Text('种类'),
                    ),
                    TextButton(
                      onPressed: () => openForm(context, const ItemForm()),
                      child: const Text('物品'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await flow.settle(t);
      await t.tap(find.text('收支'));
      await flow.settle(t);
      expect(find.byType(SegmentedButton<String>), findsOneWidget);
      await t.enterText(flow.field('分类名称'), '合成分类');
      await t.tap(find.byType(CategoryIconField));
      await t.pumpAndSettle();
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      expect(find.textContaining('通用分类'), findsOneWidget);
      await t.tap(find.byType(CategoryIconField));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).last, '相机');
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(ChoiceChip, '相机'));
      await t.pumpAndSettle();
      await t.tap(find.text('保存'));
      await flow.settle(t);
      var row = (await t.runAsync(() => db.select(db.categories).get()))!
          .singleWhere((c) => c.name == '合成分类');
      await t.runAsync(
        () => LedgerRepository(db).saveCategory('合成改名', row.kind, id: row.id),
      );
      final prefs = await t.runAsync(() => db.select(db.preferences).get());
      expect(
        prefs!.singleWhere((p) => p.key == 'category_icons').value,
        contains('camera'),
      );
      await t.tap(find.text('种类'));
      await flow.settle(t);
      await t.enterText(flow.field('种类名称'), '合成种类');
      await t.tap(find.byType(CategoryIconField));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).last, '电脑');
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(ChoiceChip, '电脑'));
      await t.pumpAndSettle();
      await t.tap(find.text('保存'));
      await flow.settle(t);
      await t.tap(find.text('物品'));
      await flow.settle(t);
      final chip = t.widget<FilterChip>(
        find.widgetWithText(FilterChip, '合成种类'),
      );
      expect((chip.avatar! as Icon).icon, categoryIcon('', iconId: 'computer'));
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(milliseconds: 1));
    },
  );
  testWidgets(
    'home category filter follows shared order without reloading ledger queries',
    (t) async {
      final db = await flow.database(t);
      await t.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: HomePage()),
        ),
      );
      await flow.settle(t);
      final before = (await t.runAsync(
        () => LedgerRepository(db).watchCategories().first,
      ))!.where((c) => c.kind == 'expense').map((c) => c.id).toList();
      await t.runAsync(
        () =>
            LedgerRepository(db)
                .reorderCategories('expense', before.reversed.toList()),
      );
      await flow.settle(t);
      final filter = find.widgetWithText(Chip, '全部分类');
      await flow.showField(t, filter);
      await t.tap(filter);
      await t.pumpAndSettle();
      final choices = t
          .widgetList<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>))
          .where((item) => before.contains(item.value))
          .map((item) => item.value);
      expect(choices, before.reversed);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(milliseconds: 1));
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'management and forms render 320px large text ${brightness.name}',
      (t) async {
        t.view.physicalSize = const Size(320, 844);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = 1.6;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await (FontLoader(
          'NotoSansSC',
        )..addFont(rootBundle.load('assets/fonts/NotoSansSC.ttf'))).load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        final db = await flow.database(t);
        final boundary = GlobalKey();
        final cases = <String, Widget>{
          'categories': const CategoriesPage(),
          'item-categories': const ItemCategoriesPage(),
          'category-form': const CategoryForm(),
          'item-category-form': const ItemCategoryForm(),
          'item-form': const ItemForm(),
        };
        for (final entry in cases.entries) {
          await t.pumpWidget(
            ProviderScope(
              key: UniqueKey(),
              overrides: [databaseProvider.overrideWithValue(db)],
              child: MaterialApp(
                theme: appTheme(brightness),
                builder: (context, child) =>
                    RepaintBoundary(key: boundary, child: child),
                home: entry.value,
              ),
            ),
          );
          await flow.settle(t);
          expect(t.takeException(), isNull);
          await t.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory('.tooling/screenshots').create(recursive: true);
            await File(
              '.tooling/screenshots/${entry.key}-${brightness.name}-320.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
          await t.pumpWidget(const SizedBox.shrink());
          await t.pump(const Duration(milliseconds: 1));
        }
      },
    );
  }
}
