import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/app/app.dart';
import 'package:so_account/app/providers/providers.dart';
import 'package:so_account/app/theme/app_theme.dart';
import 'package:so_account/app/widgets.dart';
import 'package:so_account/core/time/business_date.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/inventory/data/inventory_repository.dart';
import 'package:so_account/features/inventory/presentation/inventory_page.dart';
import 'package:so_account/features/inventory/presentation/item_form.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';
import 'package:so_account/features/ledger/presentation/accounts_page.dart';
import 'package:so_account/features/ledger/presentation/entry_form.dart';
import 'package:so_account/features/ledger/presentation/home_page.dart';
import 'package:so_account/platform/media/media_store.dart';

Future<void> settle(WidgetTester t) async {
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await t.pumpAndSettle();
}

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

void phone(WidgetTester t, {double width = 390, double scale = 1}) {
  t.view.physicalSize = Size(width, 844);
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> openTestForm(WidgetTester t, AppDatabase db, Widget form) async {
  await t.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: appTheme(Brightness.light),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => openForm(context, form),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('打开'));
  await settle(t);
}

void main() {
  testWidgets(
    'large daily income and expense fit the calendar with enlarged text',
    (t) async {
      phone(t, width: 320, scale: 1.4);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() async {
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(milliseconds: 1));
        await t.runAsync(db.close);
      });
      await t.runAsync(() async {
        final repo = LedgerRepository(db);
        final id = await repo.saveAccount(
          name: '一个很长的日常银行账户名称',
          kind: '资金账户',
          channel: '现金',
          currency: 'CNY',
          openingBalance: 0,
        );
        for (final kind in [EntryKind.income, EntryKind.expense]) {
          await repo.saveEntry(
            kind: kind,
            amount: 999999999999,
            accountId: id,
            categoryId: '${kind.name}-0',
            date: dateKey(DateTime.now()),
            note: '一段很长的备注用于验证窄屏金额和摘要不会互相挤压',
          );
        }
      });
      await t.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: appTheme(Brightness.light),
            home: const HomePage(),
          ),
        ),
      );
      await settle(t);
      expect(t.takeException(), isNull);
      await t.tap(find.byTooltip('收起月历'));
      await settle(t);
      await t.ensureVisible(find.byType(EntryTile).first);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(milliseconds: 1));
    },
  );
  testWidgets(
    'six-week calendar and first record fit together; calendar can collapse',
    (t) async {
      phone(t);
      await (FontLoader(
        'NotoSansSC',
      )..addFont(rootBundle.load('assets/fonts/NotoSansSC.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() async {
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(milliseconds: 1));
        await t.runAsync(db.close);
      });
      final repo = LedgerRepository(db);
      var month = DateTime(DateTime.now().year, DateTime.now().month);
      var moves = 0;
      while ((month.weekday -
                  1 +
                  DateTime(month.year, month.month + 1, 0).day +
                  6) ~/
              7 !=
          6) {
        month = DateTime(month.year, month.month + 1);
        moves++;
      }
      await t.runAsync(() async {
        final id = await repo.saveAccount(
          name: '日常钱包',
          kind: '资金账户',
          channel: '现金',
          currency: 'CNY',
          openingBalance: 500000,
        );
        await repo.saveEntry(
          kind: EntryKind.expense,
          amount: 2850,
          accountId: id,
          categoryId: 'expense-0',
          date: dateKey(month),
          note: '午饭',
        );
        await repo.setBudget(monthKey(month), 'CNY', 100000);
      });
      final boundary = GlobalKey();
      await t.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: RepaintBoundary(key: boundary, child: const SoAccountApp()),
        ),
      );
      await settle(t);
      for (var i = 0; i < moves; i++) {
        await t.tap(find.byTooltip('下个月'));
        await settle(t);
      }
      final record = find.byType(EntryTile);
      expect(record, findsOneWidget);
      expect(
        t.getBottomRight(record).dy,
        lessThanOrEqualTo(t.getTopLeft(find.byType(NavigationBar)).dy),
      );
      expect(
        find.byKey(ValueKey('calendar-${dateKey(month)}')),
        findsOneWidget,
      );
      await t.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('.tooling/screenshots').create(recursive: true);
        await File('.tooling/screenshots/compact-six-week.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      final before = t.getTopLeft(record).dy;
      await t.tap(find.byTooltip('收起月历'));
      await settle(t);
      expect(find.byKey(ValueKey('calendar-${dateKey(month)}')), findsNothing);
      expect(t.getTopLeft(record).dy, lessThan(before - 200));
      await t.tap(find.byTooltip('展开月历'));
      await settle(t);
      expect(
        find.byKey(ValueKey('calendar-${dateKey(month)}')),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets(
    'ledger filters recover, budget errors keep input, and menu deletes with confirmation',
    (t) async {
      phone(t);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() async {
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(milliseconds: 1));
        await t.runAsync(db.close);
      });
      final repo = LedgerRepository(db);
      await t.runAsync(() async {
        final id = await repo.saveAccount(
          name: '钱包',
          kind: '资金账户',
          channel: '现金',
          currency: 'CNY',
          openingBalance: 10000,
        );
        await repo.saveEntry(
          kind: EntryKind.expense,
          amount: 2850,
          accountId: id,
          categoryId: 'expense-0',
          date: dateKey(DateTime.now()),
          note: '午饭',
        );
      });
      await t.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: appTheme(Brightness.light),
            home: const HomePage(),
          ),
        ),
      );
      await settle(t);
      await t.tap(find.text('预算：未设置  ›'));
      await t.pumpAndSettle();
      await t.enterText(field('预算金额'), 'abc');
      await t.tap(find.text('保存'));
      await settle(t);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(t.widget<TextField>(field('预算金额')).controller!.text, 'abc');
      expect(
        t.widget<TextField>(field('预算金额')).decoration!.errorText,
        isNotNull,
      );
      await t.enterText(field('预算金额'), '300');
      await t.tap(find.text('保存'));
      await settle(t);
      expect(
        (await t.runAsync(() => db.select(db.budgets).get()))!.single.amount,
        30000,
      );
      await t.enterText(find.byType(TextField), '没有这笔');
      await settle(t);
      await t.ensureVisible(find.text('清除筛选'));
      await t.tap(find.text('清除筛选'));
      await settle(t);
      await t.ensureVisible(find.byType(EntryTile));
      await t.tap(find.byTooltip('账目操作'));
      await t.pumpAndSettle();
      expect(find.text('记物'), findsOneWidget);
      await t.tap(find.text('删除账目'));
      await t.pumpAndSettle();
      await t.tap(find.text('取消'));
      await settle(t);
      expect((await t.runAsync(() => db.select(db.entries).get()))!.length, 1);
      await t.tap(find.byTooltip('账目操作'));
      await t.pumpAndSettle();
      await t.tap(find.text('删除账目'));
      await t.pumpAndSettle();
      await t.tap(find.text('确认'));
      await settle(t);
      expect(await t.runAsync(() => db.select(db.entries).get()), isEmpty);
      expect((await t.runAsync(repo.balances))!.values.single, 10000);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets(
    'foreign-currency account, item and entry forms persist the parent currency',
    (t) async {
      phone(t, width: 320, scale: 1.4);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() async {
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(milliseconds: 1));
        await t.runAsync(db.close);
      });
      await t.runAsync(
        () => LedgerRepository(db).saveAccount(
          name: '人民币钱包',
          kind: '资金账户',
          channel: '现金',
          currency: 'CNY',
          openingBalance: 0,
        ),
      );
      await openTestForm(t, db, const AccountForm(initialCurrency: 'USD'));
      await t.enterText(field('账户名称'), '美元钱包和一个较长的账户名称');
      await t.tap(find.text('保存'));
      await settle(t);
      final accounts = (await t.runAsync(() => db.select(db.accounts).get()))!;
      final usd = accounts.singleWhere((a) => a.currency == 'USD');
      await openTestForm(t, db, const ItemForm(initialCurrency: 'USD'));
      await t.enterText(field('物品名称'), '美元物品');
      await t.tap(find.text('保存'));
      await settle(t);
      expect(
        (await t.runAsync(() => db.select(db.items).get()))!.single.currency,
        'USD',
      );
      await openTestForm(t, db, const EntryForm(initialCurrency: 'USD'));
      final accountField = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            w.key == ValueKey('account-${usd.id}'),
      );
      expect(accountField, findsOneWidget);
      await t.scrollUntilVisible(
        find.text('7'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.tap(find.text('7').first);
      await t.tap(find.text('保存'));
      await settle(t);
      final entry = (await t.runAsync(() => db.select(db.entries).get()))!
          .single;
      expect(entry.accountId, usd.id);
      expect(entry.amount, 700);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets('missing foreign currency offers the matching account form', (
    t,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(milliseconds: 1));
      await t.runAsync(db.close);
    });
    await t.runAsync(
      () => LedgerRepository(db).saveAccount(
        name: '人民币钱包',
        kind: '资金账户',
        channel: '现金',
        currency: 'CNY',
        openingBalance: 0,
      ),
    );
    await openTestForm(t, db, const EntryForm(initialCurrency: 'JPY'));
    await t.tap(find.text('先添加JPY账户'));
    await settle(t);
    await t.enterText(field('账户名称'), '日元钱包');
    await t.tap(find.text('保存'));
    await settle(t);
    await t.scrollUntilVisible(
      field('金额 · JPY'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
    expect(field('金额 · JPY'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(milliseconds: 1));
  });

  testWidgets(
    'compact inventory menus combine filters and clear without hiding unused items',
    (t) async {
      phone(t, width: 320, scale: 1.4);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() async {
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(milliseconds: 1));
        await t.runAsync(db.close);
      });
      await t.runAsync(() async {
        final repo = InventoryRepository(db);
        await repo.save(
          name: '绿茶',
          category: '食物',
          currency: 'CNY',
          useType: 'consumable',
          status: 'unused',
        );
        await repo.save(name: '相机', category: '数码产品', currency: 'CNY');
      });
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            mediaProvider.overrideWith(
              (ref) async => MediaStore(Directory.systemTemp),
            ),
          ],
          child: MaterialApp(
            theme: appTheme(Brightness.light),
            home: const InventoryPage(),
          ),
        ),
      );
      await settle(t);
      expect(find.text('2 件物品'), findsOneWidget);
      await t.tap(find.byType(ChoiceFilter).first);
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(CheckedPopupMenuItem<String>, '消耗品'));
      await settle(t);
      expect(find.text('1 件物品'), findsOneWidget);
      await t.tap(find.byTooltip('筛选物品种类'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(CheckedPopupMenuItem<String>, '数码产品'));
      await settle(t);
      expect(find.text('0 件物品'), findsOneWidget);
      await t.tap(find.byTooltip('清除物品筛选'));
      await settle(t);
      expect(find.text('2 件物品'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(milliseconds: 1));
    },
  );
}
