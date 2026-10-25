import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/core/appearance.dart';
import 'package:so_account/core/time/business_date.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';
import 'package:so_account/features/ledger/presentation/account_detail_page.dart';
import 'package:so_account/features/ledger/presentation/accounts_page.dart';
import 'package:so_account/features/ledger/presentation/entry_form.dart';
import 'package:so_account/features/settings/presentation/settings_page.dart';

import 'exposed_accounts_ui_test.dart' as qa;

void main() {
  for (final scenario in [
    (AppPalette.classic, Brightness.light, 390.0),
    (AppPalette.cucumber, Brightness.dark, 390.0),
    (AppPalette.sky, Brightness.light, 320.0),
    (AppPalette.lavender, Brightness.dark, 320.0),
  ]) {
    testWidgets(
      'archive, inspect, restore and permanently delete in ${scenario.$1}',
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
        final db = AppDatabase(NativeDatabase.memory());
        final repo = LedgerRepository(db);
        addTearDown(() async {
          await t.pumpWidget(const SizedBox.shrink());
          await t.pump(const Duration(milliseconds: 1));
          await t.runAsync(db.close);
        });
        late String id;
        await t.runAsync(() async {
          id = await repo.saveAccount(
            name: '合成旧钱包',
            kind: '资金账户',
            channel: '现金',
            currency: 'CNY',
            openingBalance: 10000,
          );
          await repo.saveAccount(
            name: '合成日常卡',
            kind: '资金账户',
            channel: '银行卡',
            currency: 'CNY',
            openingBalance: 20000,
          );
          await repo.saveEntry(
            kind: EntryKind.expense,
            amount: 500,
            accountId: id,
            categoryId: 'expense-0',
            date: dateKey(DateTime.now()),
            note: '合成历史记录',
          );
        });
        final boundary = GlobalKey();
        final suffix = '${scenario.$1.name}-${scenario.$3.toInt()}';
        Future<void> mount(Widget page) => qa.mount(
          t,
          db,
          page,
          brightness: scenario.$2,
          palette: scenario.$1,
          boundary: boundary,
        );

        await mount(AccountDetailPage(id: id));
        await t.tap(find.byTooltip('账户操作'));
        await qa.settle(t);
        expect(find.text('归档账户'), findsOneWidget);
        expect(find.text('永久删除账户'), findsOneWidget);
        await qa.capture(t, boundary, 'account-archive-actions-$suffix');
        await t.tap(find.text('取消'));
        await qa.settle(t);
        expect(find.byTooltip('编辑账户'), findsOneWidget);

        await t.tap(find.byTooltip('账户操作'));
        await qa.settle(t);
        await t.tap(find.text('永久删除账户'));
        await qa.settle(t);
        expect(find.text('永久删除「合成旧钱包」？'), findsOneWidget);
        await qa.capture(t, boundary, 'account-delete-confirm-$suffix');
        await t.tap(find.text('取消'));
        await qa.settle(t);
        expect(
          await t.runAsync(() => db.select(db.entries).get()),
          hasLength(1),
        );

        await t.tap(find.byTooltip('账户操作'));
        await qa.settle(t);
        await t.tap(find.text('归档账户'));
        await qa.settle(t);
        expect(find.byTooltip('编辑账户'), findsNothing);
        expect(find.byTooltip('余额调整'), findsNothing);
        expect(find.text('记一笔'), findsNothing);
        expect(find.textContaining('历史记录只读'), findsOneWidget);
        await qa.capture(t, boundary, 'account-archived-detail-$suffix');
        await t.tap(find.text('全部时间'));
        await qa.settle(t);
        await qa.show(t, find.textContaining('合成历史记录'));
        await t.tap(find.textContaining('合成历史记录'));
        await qa.settle(t);
        expect(find.text('历史账目'), findsOneWidget);
        expect(find.text('保存'), findsNothing);

        await mount(const AccountsPage());
        expect(find.text('合成旧钱包'), findsNothing);
        expect(find.text('200.00'), findsWidgets);
        await mount(const EntryForm());
        expect(find.textContaining('合成旧钱包'), findsNothing);

        await mount(const SettingsPage());
        await t.tap(find.text('归档账户'));
        await qa.settle(t);
        expect(find.text('合成旧钱包'), findsOneWidget);
        await qa.capture(t, boundary, 'account-archive-list-$suffix');
        expect(find.text('95.00'), findsNothing);
        await t.tap(find.text('历史明细'));
        await qa.settle(t);
        expect(find.textContaining('历史记录只读'), findsOneWidget);
        await t.tap(find.byType(BackButton));
        await qa.settle(t);
        await t.tap(find.text('恢复账户'));
        await qa.settle(t);
        expect(find.text('暂无归档账户'), findsOneWidget);
        expect(
          (await t.runAsync(() => db.select(db.entries).get()))!.length,
          1,
        );
        await mount(EntryForm(initialAccountId: id));
        await t.runAsync(() => repo.archiveAccount(id));
        await qa.settle(t);
        expect(find.text('重新选择账户'), findsOneWidget);
        expect(find.text('保存'), findsNothing);
        await t.tap(find.text('重新选择账户'));
        await qa.settle(t);
        expect(find.text('合成日常卡 · CNY'), findsOneWidget);
        await t.runAsync(() => repo.restoreAccount(id));
        await mount(AccountDetailPage(id: id));
        expect(find.byTooltip('编辑账户'), findsOneWidget);
        expect(find.text('记一笔'), findsOneWidget);
        await t.tap(find.byTooltip('账户操作'));
        await qa.settle(t);
        await t.tap(find.text('永久删除账户'));
        await qa.settle(t);
        await t.tap(find.text('永久删除'));
        await qa.settle(t);
        expect(find.text('账户已不存在'), findsOneWidget);
        expect(await t.runAsync(() => db.select(db.entries).get()), isEmpty);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(milliseconds: 1));
      },
    );
  }
}
