import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/core/time/business_date.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';
import 'package:so_account/features/ledger/presentation/entry_form.dart';

import 'exposed_accounts_ui_test.dart' as helper;

void main() {
  for (final kind in [
    EntryKind.borrow,
    EntryKind.lend,
    EntryKind.repay,
    EntryKind.collect,
  ]) {
    testWidgets(
      'debt tab keeps payer direction and original links for ${kind.name}',
      (t) async {
        t.view.physicalSize = const Size(320, 844);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = 1.4;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await (FontLoader(
          'NotoSansSC',
        )..addFont(rootBundle.load('assets/fonts/NotoSansSC.ttf'))).load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        final db = await helper.seed(t);
        final repo = LedgerRepository(db);
        final accounts = (await t.runAsync(
          () => db.select(db.accounts).get(),
        ))!;
        final wallet = accounts.singleWhere((a) => a.name == '日常现金');
        final incoming = kind == EntryKind.borrow || kind == EntryKind.repay;
        final person = accounts.singleWhere(
          (a) => a.name == (incoming ? '待还款' : '朋友往来'),
        );
        final originalId = await t.runAsync(
          () => repo.saveEntry(
            kind: incoming ? EntryKind.borrow : EntryKind.lend,
            amount: 5000,
            accountId: wallet.id,
            debtAccountId: person.id,
            date: dateKey(DateTime.now()),
          ),
        );
        final before = (await t.runAsync(() => db.select(db.entries).get()))!
            .length;
        final boundary = GlobalKey();
        await helper.mount(
          t,
          db,
          EntryForm(initialKind: kind, initialAccountId: wallet.id),
          brightness: Brightness.dark,
          boundary: boundary,
        );
        expect(find.text('付款方'), findsOneWidget);
        expect(find.text('收款方'), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('entry-swap')));
        await t.pumpAndSettle();
        final opposite = switch (kind) {
          EntryKind.borrow => EntryKind.lend,
          EntryKind.lend => EntryKind.borrow,
          EntryKind.repay => EntryKind.collect,
          _ => EntryKind.repay,
        };
        expect(find.text(opposite.label), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('entry-swap')));
        await t.pumpAndSettle();
        expect(find.text(kind.label), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('entry-debt')));
        await t.pumpAndSettle();
        await t.tap(find.widgetWithText(ListTile, person.name));
        await t.pumpAndSettle();
        await helper.capture(t, boundary, 'entry-debt-${kind.name}-320');
        if (kind.isSettlement) {
          await t.tap(find.text('6'));
          await t.tap(find.text('0'));
          await t.tap(find.text('保存'));
          await helper.settle(t);
          expect(
            (await t.runAsync(() => db.select(db.entries).get()))!.length,
            before,
          );
          await t.longPress(find.byTooltip('退格（长按清空）'));
          await t.pumpAndSettle();
          expect(
            t
                .widget<TextField>(find.byKey(const ValueKey('entry-amount')))
                .controller!
                .text,
            isEmpty,
          );
        }
        await t.tap(find.text('5'));
        await t.tap(find.text('保存'));
        await helper.settle(t);
        final rows = (await t.runAsync(() => db.select(db.entries).get()))!;
        expect(rows.length, before + 1);
        final saved = rows.last;
        expect(saved.kind, kind.name);
        expect(saved.amount, 500);
        expect(saved.accountId, wallet.id);
        expect(saved.debtAccountId, person.id);
        expect(saved.debtId, kind.isSettlement ? originalId : null);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(milliseconds: 1));
      },
    );
  }

  testWidgets(
    'transfer swaps two same-currency accounts and save another clears the amount',
    (t) async {
      final db = await helper.seed(t);
      final accounts = (await t.runAsync(() => db.select(db.accounts).get()))!;
      final wallet = accounts.singleWhere((a) => a.name == '日常现金');
      final other = accounts.singleWhere((a) => a.name == '零钱账户');
      final before = (await t.runAsync(() => db.select(db.entries).get()))!
          .length;
      await helper.mount(
        t,
        db,
        EntryForm(initialKind: EntryKind.transfer, initialAccountId: wallet.id),
      );
      await t.tap(find.byKey(const ValueKey('entry-target')));
      await t.pumpAndSettle();
      expect(find.text('美元钱包'), findsNothing);
      await t.tap(find.widgetWithText(ListTile, other.name).last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('entry-swap')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('entry-note')));
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextField, '备注'), '取消的备注');
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      expect(find.text('取消的备注'), findsNothing);
      await t.tap(find.byKey(const ValueKey('entry-note')));
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextField, '备注'), '合成测试备注');
      await t.tap(find.text('确认备注'));
      await t.pumpAndSettle();
      await t.tap(find.text('2'));
      await t.tap(find.text('再记'));
      await helper.settle(t);
      final saved = (await t.runAsync(() => db.select(db.entries).get()))!.last;
      expect(saved.accountId, other.id);
      expect(saved.targetAccountId, wallet.id);
      expect(saved.kind, 'transfer');
      expect(saved.note, '合成测试备注');
      expect(find.text('添加备注'), findsOneWidget);
      final input = t.widget<TextField>(find.byType(TextField));
      expect(input.controller!.text, isEmpty);
      await t.tap(find.text('3'));
      await t.tap(find.text('保存'));
      await helper.settle(t);
      expect(
        (await t.runAsync(() => db.select(db.entries).get()))!.length,
        before + 2,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(milliseconds: 1));
    },
  );
}
