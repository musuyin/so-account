import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/app/widgets.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';
import 'package:so_account/features/ledger/presentation/accounts_page.dart';
import 'package:so_account/features/ledger/presentation/account_detail_page.dart';
import 'package:so_account/features/ledger/presentation/entry_form.dart';
import 'package:so_account/features/ledger/presentation/finance_page.dart';
import 'package:so_account/features/statistics/presentation/statistics_page.dart';
import 'package:so_account/features/statistics/presentation/report_charts.dart';

import 'exposed_accounts_ui_test.dart' as h;

void main() {
  setUp(() async {
    await (FontLoader(
      'NotoSansSC',
    )..addFont(rootBundle.load('assets/fonts/NotoSansSC.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets(
    'investment composer creates product, cancellation discards and saves price with cost',
    (t) async {
      t.view.physicalSize = const Size(390, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final db = await h.seed(t);
      final accounts = (await t.runAsync(() => db.select(db.accounts).get()))!;
      final fund = accounts.firstWhere((a) => a.kind == '投资理财');
      final cash = accounts.firstWhere((a) => a.channel == '现金');
      await h.mount(
        t,
        db,
        EntryForm(
          initialKind: EntryKind.invest,
          initialAccountId: cash.id,
          initialTargetId: fund.id,
        ),
      );
      await t.tap(find.text('添加理财产品'));
      await h.settle(t);
      await t.enterText(h.field('产品名称'), '取消的产品');
      Navigator.of(t.element(find.byType(ProductForm))).pop();
      await h.settle(t);
      expect(
        await t.runAsync(() => db.select(db.investmentProducts).get()),
        isEmpty,
      );
      await t.tap(find.text('添加理财产品'));
      await h.settle(t);
      expect(t.widget<TextField>(h.field('产品名称')).controller!.text, isEmpty);
      await t.enterText(h.field('产品名称'), '合成投资品');
      await t.tap(find.text('保存'));
      await h.settle(t);
      expect(find.widgetWithText(ChoiceChip, '合成投资品'), findsOneWidget);
      await t.ensureVisible(h.field('当次单价 / 股价（选填）'));
      await t.enterText(h.field('当次单价 / 股价（选填）'), '9.125');
      FocusManager.instance.primaryFocus?.unfocus();
      await t.tap(find.text('3').last);
      await t.tap(find.text('0').last);
      await t.tap(find.text('再记'));
      await h.settle(t);
      final rows = (await t.runAsync(() => db.select(db.entries).get()))!;
      final invested = rows.singleWhere((e) => e.kind == 'invest');
      expect(invested.amount, 3000);
      expect(invested.unitPrice, '9.125');
      expect(invested.targetAccountId, fund.id);
      expect(
        invested.investmentProductId,
        (await t.runAsync(() => db.select(db.investmentProducts).get()))!
            .single
            .id,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(milliseconds: 1));
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'credit limit renders and stays private across account details $brightness',
      (t) async {
        t.view.physicalSize = const Size(320, 1000);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final db = await h.seed(t);
        final credit = (await t.runAsync(() => db.select(db.accounts).get()))!
            .firstWhere((a) => a.kind == '信贷账户');
        await t.runAsync(
          () => LedgerRepository(db).saveAccount(
            id: credit.id,
            name: credit.name,
            kind: credit.kind,
            channel: credit.channel,
            currency: credit.currency,
            openingBalance: credit.openingBalance,
            creditLimit: 100000,
          ),
        );
        final boundary = GlobalKey();
        await h.mount(
          t,
          db,
          const AccountsPage(),
          brightness: brightness,
          boundary: boundary,
        );
        await t.scrollUntilVisible(
          find.text('额度'),
          250,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 30,
        );
        expect(find.text('1000.00'), findsOneWidget);
        expect(find.text('400.00'), findsOneWidget);
        await h.capture(t, boundary, 'v170-credit-${brightness.name}-320');
        await t.scrollUntilVisible(
          find.byTooltip('隐藏金额'),
          -250,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 30,
        );
        await t.tap(find.byTooltip('隐藏金额'));
        await h.settle(t);
        await t.scrollUntilVisible(
          find.text(credit.name),
          250,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 30,
        );
        expect(find.text('1000.00'), findsNothing);
        expect(find.text('400.00'), findsNothing);
        await t.tap(find.text(credit.name));
        await h.settle(t);
        expect(find.byType(AccountDetailPage), findsOneWidget);
        expect(find.text('信贷额度'), findsOneWidget);
        expect(find.text('1000.00'), findsNothing);
        await t.tap(find.byTooltip('显示金额'));
        await h.settle(t);
        expect(find.text('1000.00'), findsOneWidget);
        expect(find.text('账面已用'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(milliseconds: 1));
      },
    );
    testWidgets('finance operations visible and usable $brightness', (t) async {
      t.view.physicalSize = const Size(390, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final db = await h.seed(t);
      final accounts = await t.runAsync(() => db.select(db.accounts).get());
      final cash = accounts!.firstWhere((a) => a.channel == '现金');
      final claimAccount = accounts.firstWhere((a) => a.channel == '报销');
      final fund = accounts.firstWhere((a) => a.kind == '投资理财');
      await t.runAsync(() async {
        final r = LedgerRepository(db);
        final product = await r.saveInvestmentProduct(
          accountId: fund.id,
          name: '合成股票',
          kind: '股票',
        );
        await r.saveEntry(
          kind: EntryKind.invest,
          amount: 8000,
          accountId: cash.id,
          targetAccountId: fund.id,
          investmentProductId: product,
          unitPrice: '18.75',
          date: '2026-10-12',
        );
      });
      final boundary = GlobalKey();
      await h.mount(
        t,
        db,
        const EntryForm(),
        brightness: brightness,
        boundary: boundary,
      );
      for (final tab in ['支出', '收入', '转账', '债务', '报销', '投资']) {
        expect(
          find.byKey(ValueKey('entry-tab-$tab')).hitTestable(),
          findsOneWidget,
        );
      }
      final dateRect = t.getRect(find.byKey(const ValueKey('entry-date')));
      final accountRect = t.getRect(
        find.byKey(const ValueKey('entry-account-shortcut')),
      );
      expect(accountRect.left - dateRect.right, greaterThanOrEqualTo(8));
      expect(find.byKey(const ValueKey('entry-date')), findsOneWidget);
      await h.capture(t, boundary, 'v170-entry-${brightness.name}-390');
      await t.tap(find.byKey(const ValueKey('entry-tab-报销')));
      await h.settle(t);
      expect(find.text('报销垫付'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('entry-debt')));
      await h.settle(t);
      await t.tap(find.text(claimAccount.name));
      await h.settle(t);
      await t.tap(find.text('2').last);
      await t.tap(find.text('5').last);
      await t.tap(find.text('再记'));
      await h.settle(t);
      final claimRows = await t.runAsync(() => db.select(db.entries).get());
      expect(
        claimRows!.where((e) => e.kind == 'reimburse').single.amount,
        2500,
      );
      await h.mount(
        t,
        db,
        FinancePage(investment: false, currency: 'CNY'),
        brightness: brightness,
        boundary: boundary,
      );
      expect(find.text('收到报销款'), findsOneWidget);
      await h.capture(t, boundary, 'v170-reimbursement-${brightness.name}');
      await t.tap(find.text('收到报销款'));
      await h.settle(t);
      await t.tap(find.text('1').last);
      await t.tap(find.text('0').last);
      await t.tap(find.text('保存'));
      await h.settle(t);
      final receiptRows = await t.runAsync(() => db.select(db.entries).get());
      expect(
        receiptRows!.where((e) => e.kind == 'reimbursement').single.amount,
        1000,
      );
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump();
      await h.mount(
        t,
        db,
        FinancePage(investment: true, currency: 'CNY'),
        brightness: brightness,
        boundary: boundary,
      );
      expect(find.text('合成股票'), findsOneWidget);
      await h.capture(t, boundary, 'v170-investments-${brightness.name}');
      await t.tap(find.byTooltip('隐藏金额'));
      await h.settle(t);
      expect(find.textContaining('18.75'), findsNothing);
      expect(find.textContaining('80.00'), findsNothing);
      expect(find.text('单价 ••••'), findsOneWidget);
      await h.mount(
        t,
        db,
        const StatisticsPage(),
        brightness: brightness,
        boundary: boundary,
      );
      await t.scrollUntilVisible(
        find.byType(CategoryPie),
        300,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 30,
      );
      await t.pumpAndSettle();
      final ring = t.getSize(find.byType(CategoryPie));
      expect(ring.width, greaterThan(320));
      await h.capture(t, boundary, 'v170-statistics-${brightness.name}');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(milliseconds: 1));
    });
    testWidgets('narrow large text entry and finance metadata $brightness', (
      t,
    ) async {
      t.view.physicalSize = const Size(320, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final db = await h.seed(t);
      final boundary = GlobalKey();
      Widget scaled(Widget child) => MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: child,
      );
      await h.mount(
        t,
        db,
        scaled(const EntryForm()),
        brightness: brightness,
        boundary: boundary,
      );
      expect(
        find.byKey(const ValueKey('entry-tab-投资')).hitTestable(),
        findsOneWidget,
      );
      await h.capture(t, boundary, 'v170-entry-${brightness.name}-320-2x');
      await t.tap(find.byKey(const ValueKey('entry-tab-投资')));
      await h.settle(t);
      await h.capture(
        t,
        boundary,
        'v170-invest-form-${brightness.name}-320-2x',
      );
      expect(t.takeException(), isNull);
      await h.mount(
        t,
        db,
        scaled(const AccountsPage()),
        brightness: brightness,
        boundary: boundary,
      );
      await h.capture(t, boundary, 'v170-accounts-${brightness.name}-320-2x');
      expect(t.takeException(), isNull);
      await h.mount(
        t,
        db,
        scaled(
          const Scaffold(body: ParameterRow(['分类名称较长', '1234.00', '25.0%'])),
        ),
        brightness: brightness,
        boundary: boundary,
      );
      expect(t.takeException(), isNull);
    });
  }
}
