import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/app/category_reordering.dart';
import 'package:so_account/core/category_preferences.dart';
import 'package:so_account/features/ledger/presentation/category_icon_picker.dart';
import 'package:so_account/features/ledger/presentation/category_icons.dart';

Future<void> drag(
  WidgetTester t,
  String from,
  String to, {
  bool cancel = false,
}) async {
  final start = t.getCenter(find.byKey(ValueKey('tile-$from')).first);
  final end = t.getCenter(find.byKey(ValueKey('tile-$to')).first);
  final gesture = await t.startGesture(start);
  await t.pump(const Duration(milliseconds: 600));
  await gesture.moveTo(end);
  await t.pump(const Duration(milliseconds: 200));
  if (cancel) {
    await gesture.moveTo(const Offset(2, 2));
    await t.pump();
    await gesture.cancel();
  } else {
    await gesture.up();
  }
  await t.pumpAndSettle();
}

Widget grid(
  List<String> ids,
  Future<void> Function(List<String>) save, {
  VoidCallback? onSelect,
}) => ReorderableCategoryGrid(
  ids: ids,
  label: (id) => id,
  onReorder: save,
  builder: (id) => InkWell(
    key: ValueKey('tile-$id'),
    onTap: onSelect,
    child: Column(children: [const Icon(Icons.category), Text(id)]),
  ),
);

void main() {
  test(
    'order reconciles duplicates, missing values and new IDs without loss',
    () {
      expect(resolveCategoryOrder(['a', 'b', 'c'], ['c', 'gone', 'c']), [
        'c',
        'a',
        'b',
      ]);
      expect(decodeCategoryOrder('["b","b","deleted"]'), ['b', 'b', 'deleted']);
      expect(() => decodeCategoryOrder('[1]'), throwsFormatException);
      expect(() => decodeCategoryIcons('{"x":false}'), throwsFormatException);
      expect(categoryIconCatalog, hasLength(64));
      expect(categoryIconCatalog.map((o) => o.id).toSet(), hasLength(64));
      expect(
        categoryIcon('工资', iconId: 'future-icon'),
        Icons.category_outlined,
      );
      expect(categoryIcon('工资'), Icons.work_outline);
    },
  );

  testWidgets(
    'cross-row drag saves once without selecting; cancellation does not save',
    (t) async {
      final saved = <List<String>>[];
      var selected = 0;
      final ids = List.generate(10, (i) => '分类$i');
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                grid(
                  ids,
                  (v) async => saved.add(v),
                  onSelect: () => selected++,
                ),
              ],
            ),
          ),
        ),
      );
      await drag(t, ids.first, ids[7]);
      expect(saved, hasLength(1));
      expect(saved.single.indexOf(ids.first), 7);
      expect(selected, 0);
      final after = t.getTopLeft(find.byKey(ValueKey('tile-${ids.first}')));
      await drag(t, ids.first, ids[2], cancel: true);
      expect(saved, hasLength(1));
      expect(t.getTopLeft(find.byKey(ValueKey('tile-${ids.first}'))), after);
      expect(selected, 0);
    },
  );

  testWidgets('save failure restores grid and explains failure', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              grid(['甲', '乙', '丙'], (_) async => throw StateError('disk full')),
            ],
          ),
        ),
      ),
    );
    final before = t.getTopLeft(find.byKey(const ValueKey('tile-甲')));
    await drag(t, '甲', '丙');
    expect(t.getTopLeft(find.byKey(const ValueKey('tile-甲'))), before);
    expect(find.text('排序保存失败，已恢复原顺序，请重试'), findsOneWidget);
  });

  testWidgets('edge dragging scrolls grid; cancel leaves source order', (
    t,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final saved = <List<String>>[];
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 280,
            child: ListView(
              controller: controller,
              children: [
                grid(
                  List.generate(60, (i) => '分类$i'),
                  (v) async => saved.add(v),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final gesture = await t.startGesture(
      t.getCenter(find.byKey(const ValueKey('tile-分类0'))),
    );
    await t.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(const Offset(120, 270));
    await t.pump(const Duration(milliseconds: 500));
    expect(controller.offset, greaterThan(0));
    await gesture.moveTo(const Offset(2, 500));
    await gesture.cancel();
    await t.pumpAndSettle();
    expect(saved, isEmpty);
  });

  testWidgets('accessible up/down actions use the same save callback', (
    t,
  ) async {
    final saved = <List<String>>[];
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: grid(['甲', '乙'], (v) async => saved.add(v))),
      ),
    );
    final semantics = t
        .widgetList<Semantics>(find.byType(Semantics))
        .where((s) => s.properties.customSemanticsActions?.isNotEmpty ?? false)
        .first;
    final actions = semantics.properties.customSemanticsActions!;
    actions.entries.firstWhere((e) => e.key.label == '下移').value();
    await t.pumpAndSettle();
    expect(saved.single, ['乙', '甲']);
  });

  testWidgets(
    'management drag is isolated to its group and rolls back on failure',
    (t) async {
      final saved = <String>[];
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CategoryManagementList(
              groups: const [
                CategoryManagementGroup('expense', '支出', ['甲', '乙', '丙']),
                CategoryManagementGroup('income', '收入', ['丁']),
              ],
              onReorder: (kind, ids) async {
                saved.add(kind);
                throw StateError('disk');
              },
              builder: (id) =>
                  ListTile(key: ValueKey('tile-$id'), title: Text(id)),
            ),
          ),
        ),
      );
      final before = t.getTopLeft(find.byKey(const ValueKey('tile-甲')));
      await drag(t, '甲', '丙');
      expect(saved, ['expense']);
      expect(t.getTopLeft(find.byKey(const ValueKey('tile-甲'))), before);
      expect(find.text('排序保存失败，已恢复原顺序，请重试'), findsOneWidget);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets('icon picker renders 320px large text ${brightness.name}', (
      t,
    ) async {
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
      final boundary = GlobalKey();
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness, fontFamily: 'NotoSansSC'),
          builder: (context, child) =>
              RepaintBoundary(key: boundary, child: child),
          home: const Scaffold(body: CategoryIconPicker(value: 'restaurant')),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('.tooling/screenshots').create(recursive: true);
        await File(
          '.tooling/screenshots/category-icons-${brightness.name}-320.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await t.enterText(find.byType(TextField), '电脑');
      await t.pumpAndSettle();
      expect(find.widgetWithText(ChoiceChip, '电脑'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '餐饮'), findsNothing);
    });
  }
}
