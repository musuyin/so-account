import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/core/appearance.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';
import 'package:so_account/features/ledger/presentation/accounts_page.dart';
import 'package:so_account/features/ledger/presentation/finance_page.dart';
import 'package:so_account/features/ledger/presentation/home_page.dart';
import 'package:so_account/features/importing/presentation/import_balances_page.dart';
import 'package:so_account/features/settings/presentation/archived_accounts_page.dart';
import 'package:so_account/features/statistics/data/statistics_repository.dart';
import 'package:so_account/features/statistics/presentation/report_charts.dart';

import 'current_value_calendar_sort_ui_test.dart' as rendering;
import 'exposed_accounts_ui_test.dart' as h;

void main() {
  setUp(rendering.fonts);
  for (final brightness in Brightness.values) {
    testWidgets('category chart omits currency in $brightness', (t) async {
      t.view.physicalSize = const Size(320, 900);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      final db = await h.seed(t);
      final boundary = GlobalKey();
      await h.mount(
        t,
        db,
        Scaffold(
          appBar: AppBar(
            title: const Text('统计'),
            actions: const [
              Center(child: Text('CNY')),
              SizedBox(width: 16),
            ],
          ),
          body: ListView(
            children: [
              CategoryPie(
                categories: [
                  CategoryComparison('a', '合成分类甲', 'expense', 1234, 0),
                  CategoryComparison('b', '合成分类乙', 'expense', 5678, 0),
                ],
                currency: 'CNY',
              ),
            ],
          ),
        ),
        brightness: brightness,
        boundary: boundary,
      );
      expect(find.text('CNY'), findsOneWidget);
      expect(find.text('69.12'), findsOneWidget);
      expect(find.text('零基线，点击图形查看数值'), findsNothing);
      await h.capture(t, boundary, 'v211-category-${brightness.name}-320');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(milliseconds: 1));
    });
  }
  for (final palette in AppPalette.values) {
    for (final brightness in Brightness.values) {
      for (final investment in [true, false]) {
        testWidgets(
          'finance currency filtering, precision and privacy $investment $palette $brightness',
          (t) async {
            t.view.physicalSize = const Size(320, 900);
            t.view.devicePixelRatio = 1;
            t.platformDispatcher.textScaleFactorTestValue = 1.6;
            addTearDown(t.view.resetPhysicalSize);
            addTearDown(t.view.resetDevicePixelRatio);
            addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
            final db = await h.seed(t);
            await t.runAsync(() async {
              final repo = LedgerRepository(db);
              for (final code in ['USD', 'JPY']) {
                final wallet = await repo.saveAccount(
                  name: '$code 现金',
                  kind: '资金账户',
                  channel: '现金',
                  currency: code,
                  openingBalance: 100000,
                );
                final account = await repo.saveAccount(
                  name: '$code 合成账户',
                  kind: investment ? '投资理财' : '债务',
                  channel: investment ? '基金' : '报销',
                  currency: code,
                  openingBalance: 12345,
                );
                final product = investment
                    ? await repo.saveInvestmentProduct(
                        accountId: account,
                        name: '$code 合成产品',
                        kind: '基金',
                      )
                    : null;
                await repo.saveEntry(
                  kind: investment ? EntryKind.invest : EntryKind.reimburse,
                  amount: 700,
                  accountId: wallet,
                  targetAccountId: investment ? account : null,
                  debtAccountId: investment ? null : account,
                  investmentProductId: product,
                  date: '2026-11-01',
                );
                if (investment) {
                  await repo.updateInvestmentValue(
                    accountId: account,
                    expectedCurrency: code,
                    currentValue: 23456,
                  );
                }
              }
            });
            final boundary = GlobalKey();
            await h.mount(
              t,
              db,
              FinancePage(investment: investment, currency: 'CNY'),
              brightness: brightness,
              palette: palette,
              boundary: boundary,
            );
            Navigator.of(t.element(find.byType(FinancePage))).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    FinancePage(investment: investment, currency: 'CNY'),
              ),
            );
            await h.settle(t);
            expect(find.text('CNY'), findsOneWidget);
            expect(find.textContaining('CNY '), findsNothing);
            await t.tap(h.key('finance-currency'));
            await t.pumpAndSettle();
            expect(find.byType(ChoiceChip), findsNWidgets(6));
            Navigator.of(t.element(find.byType(ChoiceChip).first)).pop();
            await t.pumpAndSettle();
            expect(find.text('CNY'), findsOneWidget);
            for (final code in ['USD', 'JPY']) {
              await t.tap(h.key('finance-currency'));
              await t.pumpAndSettle();
              if (code == 'USD') {
                await h.capture(
                  t,
                  boundary,
                  'v211-currency-picker-$investment-${palette.name}-${brightness.name}',
                );
              }
              await t.tap(find.widgetWithText(ChoiceChip, code));
              await t.pumpAndSettle();
              expect(find.text('$code 合成账户'), findsOneWidget);
              expect(find.text(investment ? '定投记录' : '差旅报销'), findsNothing);
              expect(find.textContaining('$code 1'), findsNothing);
              expect(
                find.text(code == 'JPY' ? '13045' : '130.45'),
                findsOneWidget,
              );
              if (investment) {
                expect(
                  find.text(code == 'JPY' ? '23456' : '234.56'),
                  findsOneWidget,
                );
              }
              final semantics = t.ensureSemantics();
              await t.tap(find.byTooltip('隐藏金额'));
              await t.pumpAndSettle();
              expect(
                find.textContaining(code == 'JPY' ? '13045' : '130.45'),
                findsNothing,
              );
              expect(
                t.getSemantics(find.byType(Scaffold).first).toStringDeep(),
                isNot(contains(code == 'JPY' ? '23456' : '234.56')),
              );
              semantics.dispose();
              await t.tap(find.byTooltip('显示金额'));
              await t.pumpAndSettle();
              await h.capture(
                t,
                boundary,
                'v211-finance-$investment-$code-${palette.name}-${brightness.name}-320',
              );
            }
            await t.tap(h.key('finance-currency'));
            await t.pumpAndSettle();
            await t.tap(find.widgetWithText(ChoiceChip, 'EUR'));
            await t.pumpAndSettle();
            expect(find.text('暂无账户'), findsOneWidget);
            await t.tap(find.text(investment ? '添加理财账户' : '添加报销对象'));
            await t.pumpAndSettle();
            expect(t.state(find.byType(AccountForm)), isNotNull);
            expect(h.key('account-currency-EUR'), findsOneWidget);
            Navigator.of(t.element(find.byType(AccountForm))).pop();
            await t.pumpAndSettle();
            expect(find.text('EUR'), findsOneWidget);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox.shrink());
            await t.pump(const Duration(milliseconds: 1));
          },
        );
      }
    }
  }
  testWidgets(
    'balance review and archive isolate currencies without amount units',
    (t) async {
      final db = await h.seed(t);
      final repo = LedgerRepository(db);
      final id = (await t.runAsync(
        () => repo.saveAccount(
          name: '合成日元账户',
          kind: '资金账户',
          channel: '现金',
          currency: 'JPY',
          openingBalance: 2468,
        ),
      ))!;
      final boundary = GlobalKey();
      await h.mount(
        t,
        db,
        const ImportBalancesPage(currency: 'CNY'),
        boundary: boundary,
      );
      expect(find.text('合成日元账户'), findsNothing);
      await t.tap(h.key('balance-currency'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(ChoiceChip, 'JPY'));
      await h.settle(t);
      expect(find.text('合成日元账户'), findsOneWidget);
      expect(find.text('当前余额 2468'), findsOneWidget);
      expect(find.textContaining('JPY '), findsNothing);
      await h.capture(t, boundary, 'v211-balance-review');
      await t.runAsync(() => repo.archiveAccount(id));
      await h.mount(t, db, const ArchivedAccountsPage(), boundary: boundary);
      expect(find.text('合成日元账户'), findsNothing);
      await t.tap(h.key('archive-currency'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(ChoiceChip, 'JPY'));
      await h.settle(t);
      expect(find.text('合成日元账户'), findsOneWidget);
      expect(find.text('JPY'), findsOneWidget);
      await h.capture(t, boundary, 'v211-archive');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(milliseconds: 1));
    },
  );
  testWidgets(
    'home calendar omits explanatory legend and keeps date filtering',
    (t) async {
      final db = await h.seed(t);
      final boundary = GlobalKey();
      await h.mount(t, db, const HomePage(), boundary: boundary);
      for (final label in ['日净支出', '日净收入', '今日细框', '选中粗框']) {
        expect(find.text(label), findsNothing);
      }
      final now = DateTime.now();
      final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-02';
      await t.tap(h.key('calendar-$date'));
      await h.settle(t);
      expect(
        t.widget<Semantics>(h.key('calendar-$date')).properties.selected,
        isTrue,
      );
      await h.capture(t, boundary, 'v211-home-calendar');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(milliseconds: 1));
    },
  );
}
