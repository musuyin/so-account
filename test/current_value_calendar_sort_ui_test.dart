import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/core/appearance.dart';
import 'package:so_account/core/time/business_date.dart';
import 'package:so_account/features/inventory/data/inventory_repository.dart';
import 'package:so_account/features/inventory/presentation/inventory_page.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/presentation/account_detail_page.dart';
import 'package:so_account/features/ledger/presentation/accounts_page.dart';
import 'package:so_account/features/ledger/presentation/calendar_heatmap.dart';
import 'package:so_account/features/ledger/presentation/finance_page.dart';

import 'exposed_accounts_ui_test.dart' as support;

Future<void> fonts() async {
  await (FontLoader(
    'NotoSansSC',
  )..addFont(rootBundle.load('assets/fonts/NotoSansSC.ttf'))).load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
}

void main() {
  for (final palette in AppPalette.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'today and selection remain distinct in $palette $brightness at large text',
        (t) async {
          t.view.physicalSize = const Size(320, 800);
          t.view.devicePixelRatio = 1;
          t.platformDispatcher.textScaleFactorTestValue = 1.5;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
          await fonts();
          final db = await support.seed(t);
          final boundary = GlobalKey();
          final now = DateTime.now();
          final today = dateKey(now);
          final other = dateKey(
            DateTime(now.year, now.month, now.day == 1 ? 2 : 1),
          );
          String selected = other;
          await support.mount(
            t,
            db,
            Scaffold(
              body: StatefulBuilder(
                builder: (context, update) => Column(
                  children: [
                    LedgerCalendar(
                      month: DateTime(now.year, now.month),
                      currency: 'CNY',
                      daily: {
                        today: {'income': 12500, 'expense': 3500},
                        other: {'expense': 5000},
                      },
                      selected: selected,
                      onSelected: (date) => update(() => selected = date),
                    ),
                  ],
                ),
              ),
            ),
            brightness: brightness,
            palette: palette,
            boundary: boundary,
          );
          Border border(String date) =>
              (t
                              .widgetList<Container>(
                                find.descendant(
                                  of: support.key('calendar-$date'),
                                  matching: find.byType(Container),
                                ),
                              )
                              .firstWhere((c) => c.foregroundDecoration != null)
                              .foregroundDecoration!
                          as BoxDecoration)
                      .border!
                  as Border;
          expect(border(today).top.width, 1);
          expect(border(other).top.width, 3);
          await support.capture(
            t,
            boundary,
            'v210-calendar-${palette.name}-${brightness.name}-320',
          );
          await t.tap(support.key('calendar-$today'));
          await t.pumpAndSettle();
          expect(selected, today);
          expect(border(today).top.width, 3);
          final todayFrames = t
              .widgetList<DecoratedBox>(
                find.descendant(
                  of: support.key('calendar-$today'),
                  matching: find.byType(DecoratedBox),
                ),
              )
              .where(
                (box) =>
                    box.decoration is BoxDecoration &&
                    (box.decoration as BoxDecoration).border != null,
              );
          expect(todayFrames.length, greaterThanOrEqualTo(2));
          await support.capture(
            t,
            boundary,
            'v210-calendar-today-selected-${palette.name}-${brightness.name}-320',
          );
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox.shrink());
          await t.pump(const Duration(milliseconds: 1));
        },
      );
    }
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'investment value supports cancel, save, zero, clear and privacy in $brightness',
      (t) async {
        t.view.physicalSize = const Size(320, 900);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = 1.4;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await fonts();
        final db = await support.seed(t);
        final account = (await t.runAsync(() => db.select(db.accounts).get()))!
            .singleWhere((a) => a.kind == '投资理财');
        final repo = LedgerRepository(db);
        final boundary = GlobalKey();
        await support.mount(
          t,
          db,
          AccountDetailPage(id: account.id),
          brightness: brightness,
          boundary: boundary,
        );
        await support.show(t, find.text('更新当前资产'));
        await t.tap(find.text('更新当前资产'));
        await t.pumpAndSettle();
        await t.enterText(support.field('当前资产'), '613.25');
        await t.pumpAndSettle();
        await support.capture(
          t,
          boundary,
          'v210-investment-edit-${brightness.name}-320',
        );
        await t.tap(find.byType(BackButton));
        await support.settle(t);
        expect(
          (await t.runAsync(() => db.select(db.accounts).get()))!
              .singleWhere((a) => a.id == account.id)
              .currentValue,
          isNull,
        );
        await t.tap(find.text('更新当前资产'));
        await t.pumpAndSettle();
        await t.enterText(support.field('当前资产'), '-1');
        await t.tap(find.text('保存'));
        await t.pumpAndSettle();
        expect(find.text('请输入有效金额'), findsOneWidget);
        await t.enterText(support.field('当前资产'), '613.25');
        await t.tap(find.text('保存'));
        await support.settle(t);
        expect(find.text('613.25'), findsOneWidget);
        expect(find.text('500.00'), findsOneWidget);
        await support.capture(
          t,
          boundary,
          'v210-investment-detail-${brightness.name}-320',
        );
        final semantics = t.ensureSemantics();
        await t.tap(find.byTooltip('隐藏金额'));
        await t.pumpAndSettle();
        expect(find.textContaining('613.25'), findsNothing);
        expect(
          t.getSemantics(find.byType(Scaffold).first).toStringDeep(),
          isNot(contains('613.25')),
        );
        semantics.dispose();
        await t.tap(find.byTooltip('显示金额'));
        await t.pumpAndSettle();
        await t.tap(find.text('更新当前资产'));
        await t.pumpAndSettle();
        await t.enterText(support.field('当前资产'), '0');
        await t.tap(find.text('保存'));
        await support.settle(t);
        expect(find.text('0.00'), findsOneWidget);
        await t.tap(find.text('更新当前资产'));
        await t.pumpAndSettle();
        await support.show(t, find.text('清除当前资产记录'));
        await t.tap(find.text('清除当前资产记录'));
        await support.settle(t);
        expect(find.text('未更新'), findsOneWidget);
        await t.runAsync(
          () => repo.updateInvestmentValue(
            accountId: account.id,
            expectedCurrency: 'CNY',
            currentValue: 61325,
          ),
        );
        await support.mount(
          t,
          db,
          const FinancePage(investment: true, currency: 'CNY'),
          brightness: brightness,
          boundary: boundary,
        );
        expect(find.text('613.25'), findsOneWidget);
        await support.capture(
          t,
          boundary,
          'v210-investment-management-${brightness.name}-320',
        );
        await support.mount(
          t,
          db,
          const AccountsPage(),
          brightness: brightness,
          boundary: boundary,
        );
        await support.show(t, find.text('当前资产'));
        expect(find.text('613.25'), findsOneWidget);
        await support.capture(
          t,
          boundary,
          'v210-investment-list-${brightness.name}-320',
        );
        await support.show(t, find.byTooltip('隐藏金额'));
        await t.tap(find.byTooltip('隐藏金额'));
        await t.pumpAndSettle();
        await support.show(t, find.text('当前资产'));
        expect(find.textContaining('613.25'), findsNothing);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(milliseconds: 1));
      },
    );
  }

  testWidgets(
    'inventory exposes sorting options and restores saved ordering on reopen',
    (t) async {
      final db = await support.seed(t);
      await t.runAsync(() async {
        final repo = InventoryRepository(db);
        await repo.save(
          name: 'Alpha',
          category: '未分类',
          currency: 'CNY',
          price: 100,
        );
        await repo.save(
          name: 'Beta',
          category: '未分类',
          currency: 'CNY',
          price: 200,
        );
        await repo.saveSort('name');
      });
      await support.mount(t, db, const InventoryPage());
      expect(
        t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '按名称')).selected,
        isTrue,
      );
      await t.tap(find.text('价格从高到低'));
      await support.settle(t);
      await support.mount(t, db, const InventoryPage());
      expect(
        t
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '价格从高到低'))
            .selected,
        isTrue,
      );
      await support.show(t, find.text('Alpha'));
      expect(
        t.getTopLeft(find.text('Beta')).dy,
        lessThan(t.getTopLeft(find.text('Alpha')).dy),
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(milliseconds: 1));
    },
  );
}
