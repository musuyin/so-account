import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/app/providers/providers.dart';
import 'package:so_account/app/theme/app_theme.dart';
import 'package:so_account/app/widgets.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/inventory/domain/item_categories.dart';
import 'package:so_account/features/inventory/presentation/item_form.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/presentation/entry_form.dart';

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
final itemSwitch = find.byKey(const ValueKey('record-item-switch'));
final itemSection = find.byKey(const ValueKey('inline-purchase-item'));

Future<void> settle(WidgetTester t) async {
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await t.pumpAndSettle();
}

class RouteCounter extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;
}

Future<void> showField(WidgetTester t, Finder finder) async {
  await t.scrollUntilVisible(
    finder,
    180,
    scrollable: find.byType(Scrollable).first,
  );
  await t.ensureVisible(finder);
  await t.pumpAndSettle();
}

Future<void> selectType(WidgetTester t, String value) async {
  final dropdown = find.byKey(const ValueKey('inline-item-category'));
  await showField(t, dropdown);
  await t.tap(dropdown);
  await t.pumpAndSettle();
  await t.tap(find.text(value).last);
  await t.pumpAndSettle();
}

Future<void> enterAmount(WidgetTester t) async {
  await showField(t, find.text('7').first);
  await t.tap(find.text('7').first);
  await t.pump();
}

Future<AppDatabase> database(WidgetTester t) async {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(() async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(milliseconds: 1));
    await t.runAsync(db.close);
  });
  await t.runAsync(
    () => LedgerRepository(db).saveAccount(
      name: '美元钱包',
      kind: '资金账户',
      channel: '现金',
      currency: 'USD',
      openingBalance: 10000,
    ),
  );
  return db;
}

Future<void> open(
  WidgetTester t,
  AppDatabase db, {
  Entry? entry,
  bool recordItem = false,
  Brightness brightness = Brightness.light,
  RouteCounter? routes,
  GlobalKey? boundary,
}) async {
  await t.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: appTheme(brightness),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        navigatorObservers: [?routes],
        builder: boundary == null
            ? null
            : (context, child) => RepaintBoundary(key: boundary, child: child),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => openForm(
                context,
                EntryForm(
                  entry: entry,
                  initialCurrency: 'USD',
                  initialRecordItem: recordItem,
                ),
              ),
              child: const Text('打开记账'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('打开记账'));
  await settle(t);
}

void main() {
  for (final width in [390.0, 320.0]) {
    testWidgets(
      'inline purchase stays on one route and atomically saves at $width pixels',
      (t) async {
        t.view.physicalSize = Size(width, 844);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = width == 320 ? 1.4 : 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await (FontLoader(
          'NotoSansSC',
        )..addFont(rootBundle.load('assets/fonts/NotoSansSC.ttf'))).load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        final db = await database(t);
        final routes = RouteCounter();
        final boundary = GlobalKey();
        await open(
          t,
          db,
          brightness: width == 320 ? Brightness.dark : Brightness.light,
          routes: routes,
          boundary: boundary,
        );
        expect(itemSection, findsNothing);
        await showField(t, itemSwitch);
        final pushes = routes.pushes;
        await t.tap(itemSwitch);
        await t.pumpAndSettle();
        expect(routes.pushes, pushes);
        expect(find.byType(ItemForm), findsNothing);
        await showField(t, field('物品名称'));
        await t.enterText(field('物品名称'), '洗发水');
        await selectType(t, '日用品');
        await showField(t, itemSwitch);
        await t.tap(itemSwitch);
        await t.pumpAndSettle();
        expect(itemSection, findsNothing);
        await t.tap(itemSwitch);
        await t.pumpAndSettle();
        await showField(t, field('物品名称'));
        expect(t.widget<TextField>(field('物品名称')).controller!.text, '洗发水');
        final useType = find.byKey(const ValueKey('inline-item-use-type'));
        await showField(t, useType);
        await t.tap(useType);
        await t.pumpAndSettle();
        await t.tap(find.text('消耗品').last);
        await t.pumpAndSettle();
        for (final input in {
          '数量 / 容量 · 可留空': '500',
          '单位 · 可留空': 'ml',
          '物品价格 · USD · 可留空': '12.50',
        }.entries) {
          await showField(t, field(input.key));
          await t.enterText(field(input.key), input.value);
        }
        FocusManager.instance.primaryFocus?.unfocus();
        await showField(t, field('物品名称'));
        final position = t
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position;
        position.jumpTo(
          (position.pixels - 130).clamp(0, position.maxScrollExtent),
        );
        await t.pumpAndSettle();
        await t.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('.tooling/screenshots').create(recursive: true);
          await File(
            '.tooling/screenshots/entry-inline-item-${width.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await enterAmount(t);
        if (width == 320) {
          t.view.viewInsets = const FakeViewPadding(bottom: 260);
          addTearDown(t.view.resetViewInsets);
          await t.pumpAndSettle();
          expect(t.getBottomRight(find.text('保存')).dy, lessThan(844 - 260));
        }
        await t.tap(find.text('保存'));
        await settle(t);
        expect(find.text('打开记账'), findsOneWidget);
        final entry = (await t.runAsync(() => db.select(db.entries).get()))!
            .single;
        final item = (await t.runAsync(() => db.select(db.items).get()))!
            .single;
        final link = (await t.runAsync(
          () => db.select(db.purchaseLinks).get(),
        ))!.single;
        expect(entry.amount, 700);
        expect(item.name, '洗发水');
        expect(itemTags(item.category), ['日用品']);
        expect(item.currency, 'USD');
        expect(item.purchasedOn, entry.date);
        expect(item.price, 1250);
        expect(item.quantity, '500');
        expect(item.unit, 'ml');
        expect(link.entryId, entry.id);
        expect(link.itemId, item.id);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(milliseconds: 1));
      },
    );
  }

  for (final income in [false, true]) {
    testWidgets('hidden item draft does not save or validate; income=$income', (
      t,
    ) async {
      final db = await database(t);
      await open(t, db);
      await showField(t, itemSwitch);
      await t.tap(itemSwitch);
      await t.pumpAndSettle();
      if (income) {
        t
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await t.pumpAndSettle();
        await t.tap(find.text('收入').first);
        await t.pumpAndSettle();
        expect(itemSwitch, findsNothing);
      } else {
        await t.tap(itemSwitch);
        await t.pumpAndSettle();
      }
      await enterAmount(t);
      await t.tap(find.text('保存'));
      await settle(t);
      expect(
        (await t.runAsync(() => db.select(db.entries).get()))!.single.kind,
        income ? 'income' : 'expense',
      );
      expect(await t.runAsync(() => db.select(db.items).get()), isEmpty);
      expect(
        await t.runAsync(() => db.select(db.purchaseLinks).get()),
        isEmpty,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(milliseconds: 1));
    });
  }

  testWidgets(
    'item failure retains the form for correction; ordinary edit creates no duplicate',
    (t) async {
      final db = await database(t);
      await open(t, db, recordItem: true);
      await selectType(t, '日用品');
      await enterAmount(t);
      await t.tap(find.text('保存'));
      await settle(t);
      expect(find.byType(EntryForm), findsOneWidget);
      expect(await t.runAsync(() => db.select(db.entries).get()), isEmpty);
      await showField(t, field('物品名称'));
      await t.enterText(field('物品名称'), '水杯');
      await t.tap(find.text('保存'));
      await settle(t);
      final entry = (await t.runAsync(() => db.select(db.entries).get()))!
          .single;
      await open(t, db, entry: entry);
      await showField(t, itemSwitch);
      expect(t.widget<SwitchListTile>(itemSwitch).value, isFalse);
      await t.tap(find.text('保存'));
      await settle(t);
      expect((await t.runAsync(() => db.select(db.entries).get()))!.length, 1);
      expect((await t.runAsync(() => db.select(db.items).get()))!.length, 1);
      expect(
        (await t.runAsync(() => db.select(db.purchaseLinks).get()))!.length,
        1,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(milliseconds: 1));
    },
  );
}
