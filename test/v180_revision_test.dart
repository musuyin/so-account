import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:so_account/app/providers/providers.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';
import 'package:so_account/features/ledger/presentation/entry_form.dart';
import 'package:so_account/features/ledger/presentation/people_debts_page.dart';
import 'package:so_account/features/settings/presentation/settings_page.dart';
import 'package:so_account/features/statistics/presentation/statistics_page.dart';

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
    'category recall persists, manual selection wins, cancel does not update, archived and other currencies fall back',
    (t) async {
      t.view.physicalSize = const Size(390, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final db = await h.seed(t);
      final repo = LedgerRepository(db);
      final accounts = (await t.runAsync(() => db.select(db.accounts).get()))!;
      final cash = accounts.firstWhere(
        (a) => a.channel == '现金' && a.currency == 'CNY',
      );
      final wallet = accounts.firstWhere((a) => a.channel == '微信');
      final usd = accounts.firstWhere((a) => a.currency == 'USD');
      await t.runAsync(
        () => repo.saveEntry(
          kind: EntryKind.expense,
          amount: 200,
          accountId: wallet.id,
          categoryId: 'expense-1',
          date: '2026-10-20',
        ),
      );
      final boundary = GlobalKey();
      await h.mount(
        t,
        db,
        const EntryForm(initialCurrency: 'CNY'),
        boundary: boundary,
      );
      await t.tap(h.key('entry-category-expense-1'));
      await h.settle(t);
      expect(
        find.descendant(
          of: h.key('entry-account-shortcut'),
          matching: find.text(wallet.name),
        ),
        findsOneWidget,
      );
      await t.tap(h.key('entry-account-shortcut'));
      await h.settle(t);
      expect(find.text('余额 73.00'), findsOneWidget);
      await h.capture(t, boundary, 'v180-account-balances');
      await t.tap(find.text(cash.name).last);
      await h.settle(t);
      await h.settle(t);
      expect(
        find.descendant(
          of: h.key('entry-account-shortcut'),
          matching: find.text(cash.name),
        ),
        findsOneWidget,
      );
      await h.mount(t, db, const EntryForm(initialCurrency: 'CNY'));
      await t.tap(h.key('entry-category-expense-1'));
      await h.settle(t);
      expect(
        find.descendant(
          of: h.key('entry-account-shortcut'),
          matching: find.text(wallet.name),
        ),
        findsOneWidget,
      );
      await t.runAsync(() => repo.archiveAccount(wallet.id));
      await h.mount(t, db, const EntryForm(initialCurrency: 'CNY'));
      await t.tap(h.key('entry-category-expense-1'));
      await h.settle(t);
      expect(
        find.descendant(
          of: h.key('entry-account-shortcut'),
          matching: find.text(cash.name),
        ),
        findsOneWidget,
      );
      await t.runAsync(
        () => repo.saveEntry(
          kind: EntryKind.expense,
          amount: 100,
          accountId: usd.id,
          categoryId: 'expense-1',
          date: '2026-10-21',
        ),
      );
      await h.mount(t, db, const EntryForm(initialCurrency: 'CNY'));
      await t.tap(h.key('entry-category-expense-1'));
      await h.settle(t);
      expect(
        find.descendant(
          of: h.key('entry-account-shortcut'),
          matching: find.text(cash.name),
        ),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(milliseconds: 1));
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'consistent operation buttons, private balances, settings tiles, debt isolation and currency at top right $brightness',
      (t) async {
        t.view.physicalSize = const Size(320, 950);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = 1.4;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final db = await h.seed(t);
        final boundary = GlobalKey();
        await h.mount(
          t,
          db,
          const EntryForm(),
          brightness: brightness,
          boundary: boundary,
        );
        final expense = t.getSize(h.key('entry-tab-支出'));
        final reimburse = t.getSize(h.key('entry-tab-报销'));
        expect(reimburse.width, closeTo(expense.width, 2));
        expect(reimburse.height, closeTo(expense.height, .01));
        await h.capture(t, boundary, 'v180-entry-${brightness.name}');
        final container = ProviderScope.containerOf(
          t.element(find.byType(EntryForm)),
        );
        container.read(assetAmountsHiddenProvider.notifier).toggle();
        await t.tap(h.key('entry-account-shortcut'));
        await h.settle(t);
        expect(find.text('余额 ••••'), findsWidgets);
        expect(find.textContaining('余额 19'), findsNothing);
        await h.capture(t, boundary, 'v180-account-private-${brightness.name}');
        await h.mount(
          t,
          db,
          const PeopleDebtsPage(),
          brightness: brightness,
          boundary: boundary,
        );
        expect(find.text('报销'), findsNothing);
        expect(find.text('差旅报销'), findsNothing);
        expect(find.text('应付款'), findsOneWidget);
        expect(find.text('应收款'), findsOneWidget);
        await h.capture(t, boundary, 'v180-debt-${brightness.name}');
        await h.mount(
          t,
          db,
          const SettingsPage(),
          brightness: brightness,
          boundary: boundary,
        );
        expect(find.text('选项'), findsOneWidget);
        expect(find.text('常用'), findsNothing);
        expect(find.text('数据管理'), findsOneWidget);
        await h.capture(t, boundary, 'v180-settings-${brightness.name}');
        await t.runAsync(
          () async => LedgerRepository(db).saveEntry(
            kind: EntryKind.borrow,
            amount: 4000,
            accountId: (await db.select(db.accounts).get())
                .firstWhere((a) => a.channel == '现金' && a.currency == 'CNY')
                .id,
            date:
                '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-10',
          ),
        );
        await h.mount(
          t,
          db,
          const StatisticsPage(),
          brightness: brightness,
          boundary: boundary,
        );
        final currency = h.key('statistics-currency');
        expect(t.getRect(currency).top, lessThan(70));
        expect(t.getRect(currency).right, greaterThan(300));
        expect(find.byKey(const ValueKey('statistics-loans')), findsOneWidget);
        await h.capture(t, boundary, 'v180-loans-${brightness.name}');
        await t.tap(currency);
        await h.settle(t);
        await t.tap(find.text('USD').last);
        await h.settle(t);
        expect(
          find.descendant(of: currency, matching: find.text('USD')),
          findsOneWidget,
        );
        await h.capture(t, boundary, 'v180-statistics-${brightness.name}');
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(milliseconds: 1));
      },
    );
  }
}
