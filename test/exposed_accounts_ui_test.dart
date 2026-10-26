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
import 'package:so_account/core/appearance.dart';
import 'package:so_account/core/time/business_date.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';
import 'package:so_account/features/ledger/presentation/account_detail_page.dart';
import 'package:so_account/features/ledger/presentation/accounts_page.dart';
import 'package:so_account/features/ledger/presentation/calendar_heatmap.dart';
import 'package:so_account/features/ledger/presentation/home_page.dart';

Finder key(String value) => find.byKey(ValueKey(value));
Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

Future<void> settle(WidgetTester t) async {
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await t.pumpAndSettle();
}

Future<AppDatabase> seed(WidgetTester t) async {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(() async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(milliseconds: 1));
    await t.runAsync(db.close);
  });
  await t.runAsync(() async {
    final repo = LedgerRepository(db);
    final wallet = await repo.saveAccount(
      name: '日常现金',
      kind: '资金账户',
      channel: '现金',
      currency: 'CNY',
      openingBalance: 200000,
    );
    await repo.saveAccount(
      name: '零钱账户',
      kind: '资金账户',
      channel: '微信',
      currency: 'CNY',
      openingBalance: 7500,
    );
    await repo.saveAccount(
      name: '日常信用卡',
      kind: '信贷账户',
      channel: '信用卡',
      currency: 'CNY',
      openingBalance: -60000,
    );
    await repo.saveAccount(
      name: '差旅报销',
      kind: '债务',
      channel: '报销',
      currency: 'CNY',
      openingBalance: 12000,
    );
    await repo.saveAccount(
      name: '朋友往来',
      kind: '债务',
      channel: '应收款',
      currency: 'CNY',
      openingBalance: 25000,
    );
    await repo.saveAccount(
      name: '待还款',
      kind: '债务',
      channel: '应付款',
      currency: 'CNY',
      openingBalance: 8000,
    );
    await repo.saveAccount(
      name: '定投记录',
      kind: '投资理财',
      channel: '基金',
      currency: 'CNY',
      openingBalance: 50000,
    );
    await repo.saveAccount(
      name: '美元钱包',
      kind: '资金账户',
      channel: '现金',
      currency: 'USD',
      openingBalance: 9000,
    );
    final now = DateTime.now();
    for (final row in [
      (2, EntryKind.expense, 500),
      (4, EntryKind.expense, 2500),
      (6, EntryKind.income, 10000),
      (9, EntryKind.income, 4000),
      (9, EntryKind.expense, 1000),
      (16, EntryKind.expense, 1000),
    ]) {
      await repo.saveEntry(
        kind: row.$2,
        amount: row.$3,
        accountId: wallet,
        categoryId: '${row.$2.name}-0',
        date: dateKey(DateTime(now.year, now.month, row.$1)),
      );
    }
  });
  return db;
}

Future<void> mount(
  WidgetTester t,
  AppDatabase db,
  Widget page, {
  Brightness brightness = Brightness.light,
  AppPalette palette = AppPalette.cucumber,
  GlobalKey? boundary,
}) async {
  await t.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: appTheme(brightness, palette: palette),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: boundary == null
            ? null
            : (context, child) => RepaintBoundary(key: boundary, child: child),
        home: page,
      ),
    ),
  );
  await settle(t);
}

Future<void> capture(WidgetTester t, GlobalKey boundary, String name) async {
  await t.runAsync(() async {
    final image =
        await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('.tooling/screenshots').create(recursive: true);
    await File('.tooling/screenshots/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> show(WidgetTester t, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    t.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
    await t.pumpAndSettle();
    if (finder.evaluate().isEmpty) {
      await t.scrollUntilVisible(
        finder,
        180,
        scrollable: find.byType(Scrollable).first,
      );
    }
  }
  await t.ensureVisible(finder);
  await t.pumpAndSettle();
}

void main() {
  test('heatmap scale is monotonic and amounts retain contrast across all palettes', () {
    for (final palette in AppPalette.values) {
      for (final brightness in Brightness.values) {
        final colors = appTheme(brightness, palette: palette).colorScheme;
        expect(calendarHeatColor(colors, 0, 0, 0), colors.surface);
        expect(
          calendarHeatColor(colors, 100, 100, 0),
          colors.surfaceContainerHighest,
        );
        expect(
          calendarHeatColor(colors, 0, 10, 100),
          isNot(calendarHeatColor(colors, 0, 100, 100)),
        );
        expect(
          calendarHeatColor(colors, 0, 1000, 100),
          calendarHeatColor(colors, 0, 100, 100),
        );
        for (final net in [-100, -50, -10, 10, 50, 100]) {
          final bg = calendarHeatColor(
            colors,
            net > 0 ? net : 0,
            net < 0 ? -net : 0,
            100,
          ).computeLuminance();
          for (final text in [
            calendarIncomeColor(brightness),
            calendarExpenseColor(brightness),
            colors.onSurface,
          ]) {
            final fg = text.computeLuminance();
            final contrast = fg > bg
                ? (fg + .05) / (bg + .05)
                : (bg + .05) / (fg + .05);
            expect(
              contrast,
              greaterThanOrEqualTo(4.5),
              reason: '$palette $brightness $net $text',
            );
          }
        }
      }
    }
  });

  for (final scenario in [
    (AppPalette.classic, Brightness.light, 390.0),
    (AppPalette.cucumber, Brightness.dark, 390.0),
    (AppPalette.sky, Brightness.light, 320.0),
    (AppPalette.lavender, Brightness.dark, 320.0),
  ]) {
    testWidgets(
      'direct type and bank selection, assets and calendar render in ${scenario.$1} ${scenario.$2}',
      (t) async {
        t.view.physicalSize = Size(scenario.$3, 844);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = scenario.$3 == 320
            ? 1.4
            : 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await (FontLoader(
          'NotoSansSC',
        )..addFont(rootBundle.load('assets/fonts/NotoSansSC.ttf'))).load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        final db = await seed(t);
        final boundary = GlobalKey();
        final suffix = '${scenario.$1.name}-${scenario.$3.toInt()}';
        await mount(
          t,
          db,
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => openForm(
                  context,
                  const AccountForm(initialCurrency: 'USD'),
                ),
                child: const Text('新增'),
              ),
            ),
          ),
          brightness: scenario.$2,
          palette: scenario.$1,
          boundary: boundary,
        );
        await t.tap(find.text('新增'));
        await settle(t);
        expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
        for (final kind in accountKinds) {
          expect(find.text(kind), findsOneWidget);
        }
        await capture(t, boundary, 'account-types-$suffix');
        await show(t, key('account-type-信贷账户-信用卡'));
        await t.tap(key('account-type-信贷账户-信用卡'));
        await t.pumpAndSettle();
        await show(t, key('account-bank-cmb'));
        await t.tap(key('account-bank-cmb'));
        await t.pumpAndSettle();
        await show(t, field('账户名称'));
        await t.enterText(field('账户名称'), '备用信用卡');
        await show(t, field('初始余额'));
        await t.enterText(field('初始余额'), '-150.25');
        await t.tap(find.text('保存'));
        await settle(t);
        final saved = (await t.runAsync(() => db.select(db.accounts).get()))!
            .singleWhere((a) => a.name == '备用信用卡');
        expect(saved.kind, '信贷账户');
        expect(saved.channel, '信用卡');
        expect(saved.currency, 'USD');
        expect(saved.bank, 'cmb');
        expect(saved.openingBalance, -15025);
        await mount(
          t,
          db,
          const AccountsPage(),
          brightness: scenario.$2,
          palette: scenario.$1,
          boundary: boundary,
        );
        expect(find.text('2355.00'), findsOneWidget);
        expect(t.takeException(), isNull);
        await capture(t, boundary, 'asset-overview-$suffix');
        await mount(
          t,
          db,
          const HomePage(),
          brightness: scenario.$2,
          palette: scenario.$1,
          boundary: boundary,
        );
        expect(t.takeException(), isNull);
        final current = DateTime.now();
        double dateTop(int day) {
          final cell = key(
            'calendar-${dateKey(DateTime(current.year, current.month, day))}',
          );
          final text = find.descendant(of: cell, matching: find.text('$day'));
          return t.getTopLeft(text).dy - t.getTopLeft(cell).dy;
        }

        expect(dateTop(1), closeTo(dateTop(2), 0.01));
        expect(dateTop(2), closeTo(dateTop(6), 0.01));
        await capture(t, boundary, 'calendar-heatmap-$suffix');
        final now = DateTime.now();
        final day = dateKey(DateTime(now.year, now.month, 4));
        await show(t, key('calendar-$day'));
        await t.tap(key('calendar-$day'));
        await t.pumpAndSettle();
        final selected = find.widgetWithText(FilterChip, day);
        await show(t, selected);
        expect(t.widget<FilterChip>(selected).selected, isTrue);
        expect(find.text('$day · 1 笔'), findsOneWidget);
        await t.tap(selected);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(milliseconds: 1));
      },
    );
  }

  testWidgets(
    'asset privacy masks every amount, groups collapse, currency stays isolated and details open',
    (t) async {
      final semantics = t.ensureSemantics();
      try {
        final db = await seed(t);
        await mount(t, db, const AccountsPage());
        final wallet = (await t.runAsync(() => db.select(db.accounts).get()))!
            .singleWhere((a) => a.name == '日常现金');
        await show(t, key('account-group-资金账户'));
        await t.tap(key('account-group-资金账户'));
        await t.pumpAndSettle();
        expect(key('asset-account-${wallet.id}'), findsNothing);
        await t.tap(key('account-group-资金账户'));
        await t.pumpAndSettle();
        await t.tap(key('asset-account-${wallet.id}'));
        await settle(t);
        expect(find.byType(AccountDetailPage), findsOneWidget);
        await t.tap(find.byType(BackButton));
        await settle(t);
        await show(t, find.byTooltip('隐藏金额'));
        await t.longPress(find.text('2355.00'));
        await t.pumpAndSettle();
        await t.tap(find.byTooltip('隐藏金额'));
        await t.pumpAndSettle();
        expect(find.textContaining(RegExp(r'\d+\.\d{2}')), findsNothing);
        expect(
          t.getSemantics(find.byType(Scaffold).first).toStringDeep(),
          isNot(contains('2355.00')),
        );
        await t.tap(key('asset-currency'));
        await t.pumpAndSettle();
        await t.tap(find.text('USD').last);
        await t.pumpAndSettle();
        expect(find.text('••••'), findsWidgets);
        await t.tap(find.byTooltip('显示金额'));
        await t.pumpAndSettle();
        expect(find.text('90.00'), findsWidgets);
        expect(find.text('2355.00'), findsNothing);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(milliseconds: 1));
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'direct JPY choice formats the default zero balance without fractional digits',
    (t) async {
      final db = await seed(t);
      await mount(
        t,
        db,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => openForm(context, const AccountForm()),
              child: const Text('新增'),
            ),
          ),
        ),
      );
      await t.tap(find.text('新增'));
      await settle(t);
      await t.tap(key('account-type-资金账户-现金'));
      await t.pumpAndSettle();
      await t.tap(find.byType(DropdownButtonFormField<String>));
      await t.pumpAndSettle();
      await t.tap(find.text('JPY').last);
      await t.pumpAndSettle();
      await show(t, field('账户名称'));
      await t.enterText(field('账户名称'), '日元零钱');
      await t.tap(find.text('保存'));
      await settle(t);
      final account = (await t.runAsync(() => db.select(db.accounts).get()))!
          .singleWhere((a) => a.name == '日元零钱');
      expect(account.currency, 'JPY');
      expect(account.openingBalance, 0);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(milliseconds: 1));
    },
  );

  for (final adjustmentOnly in [false, true]) {
    testWidgets(
      'direct options protect existing account kind and currency; adjustmentOnly=$adjustmentOnly',
      (t) async {
        final db = await seed(t);
        final account = (await t.runAsync(() => db.select(db.accounts).get()))!
            .singleWhere((a) => a.name == (adjustmentOnly ? '美元钱包' : '日常现金'));
        if (adjustmentOnly) {
          await t.runAsync(
            () => LedgerRepository(db).adjustBalance(
              accountId: account.id,
              desiredBalance: 9100,
              expectedBalance: 9000,
            ),
          );
        }
        await mount(
          t,
          db,
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    openForm(context, AccountForm(account: account)),
                child: const Text('编辑'),
              ),
            ),
          ),
        );
        await t.tap(find.text('编辑'));
        await settle(t);
        await show(t, find.byType(DropdownButtonFormField<String>));
        expect(
          t
              .widget<DropdownButtonFormField<String>>(
                find.byType(DropdownButtonFormField<String>),
              )
              .onChanged,
          isNull,
        );
        await show(t, find.text('更换'));
        await t.tap(find.text('更换'));
        await t.pumpAndSettle();
        expect(key('account-type-信贷账户-信用卡'), findsNothing);
        expect(key('account-type-资金账户-银行卡'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(milliseconds: 1));
      },
    );
  }
}
