import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/features/ledger/presentation/accounts_page.dart';
import 'package:so_account/features/ledger/presentation/entry_form.dart';
import 'package:so_account/features/ledger/presentation/amount_pad.dart';
import 'package:so_account/features/settings/presentation/settings_page.dart';
import 'package:so_account/features/inventory/presentation/inventory_page.dart';
import 'package:so_account/features/goals/presentation/goals_page.dart';

import 'exposed_accounts_ui_test.dart' as helper;

void main() {
  for (final width in [390.0, 320.0]) {
    testWidgets('fixed entry controls and compact pages render at $width', (
      t,
    ) async {
      t.view.physicalSize = Size(width, 844);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = width == 320 ? 1.6 : 1;
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
      final boundary = GlobalKey();
      for (final (name, page) in <(String, Widget)>[
        ('settings', const SettingsPage()),
        ('entry', const EntryForm()),
        ('inventory', const InventoryPage()),
        ('accounts', const AccountsPage()),
        ('goals', const GoalsPage()),
      ]) {
        await helper.mount(
          t,
          db,
          page,
          brightness: width == 320 ? Brightness.dark : Brightness.light,
          boundary: boundary,
        );
        expect(t.takeException(), isNull, reason: name);
        await helper.capture(t, boundary, 'revision-$name-${width.toInt()}');
        if (name == 'settings') {
          if (width == 390) {
            expect(
              t.getTopLeft(find.text('归档账户')).dy,
              t.getTopLeft(find.text('导入')).dy,
            );
          }
          await t.tap(find.text('导出'));
          await helper.settle(t);
          expect(find.text('复制 Markdown'), findsOneWidget);
          Navigator.of(t.element(find.text('复制 Markdown'))).pop();
          await helper.settle(t);
        }
        if (name == 'entry') {
          final pad = find.byType(AmountPad);
          final before = t.getRect(pad);
          final typeBefore = t.getRect(
            find.byKey(const ValueKey('entry-tab-支出')),
          );
          expect(
            t.getTopLeft(find.text('1')).dy,
            lessThan(t.getTopLeft(find.text('4')).dy),
          );
          expect(
            t.getTopLeft(find.text('4')).dy,
            lessThan(t.getTopLeft(find.text('7')).dy),
          );
          await t.drag(find.byType(ListView), const Offset(0, -420));
          await t.pumpAndSettle();
          expect(t.getRect(pad), before);
          expect(
            t.getRect(find.byKey(const ValueKey('entry-tab-支出'))),
            typeBefore,
          );
          await t.tap(find.text('1'));
          await t.tap(find.text('2'));
          final amount = t.widget<TextField>(
            find.descendant(of: pad, matching: find.byType(TextField)),
          );
          expect(amount.controller!.text, '12');
          expect(t.takeException(), isNull);
        }
        if (name == 'inventory') {
          await t.ensureVisible(find.text('收起筛选'));
          await t.tap(find.widgetWithText(ChoiceChip, '消耗品'));
          await t.tap(find.text('收起筛选'));
          await t.pumpAndSettle();
          expect(find.widgetWithText(ChoiceChip, '消耗品'), findsNothing);
          expect(find.text('消耗品'), findsOneWidget);
          await t.tap(find.text('展开筛选'));
          await t.pumpAndSettle();
          expect(
            t
                .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '消耗品'))
                .selected,
            isTrue,
          );
        }
      }
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(milliseconds: 1));
    });
  }
  testWidgets(
    'long press reorders accounts and survives opening the page again',
    (t) async {
      t.view.physicalSize = const Size(390, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final db = await helper.seed(t);
      await helper.mount(t, db, const AccountsPage());
      final rows = find.descendant(
        of: find.byType(ReorderableListView).first,
        matching: find.byType(ReorderableDelayedDragStartListener),
      );
      final names = [
        for (final e in rows.evaluate())
          (e.widget as ReorderableDelayedDragStartListener).key,
      ];
      final start = t.getTopLeft(rows.first) + const Offset(45, 28);
      final end = t.getTopLeft(rows.at(1)) + const Offset(45, 28);
      final gesture = await t.startGesture(start);
      await t.pump(const Duration(milliseconds: 700));
      await gesture.moveTo(end + const Offset(0, 70));
      await t.pump(const Duration(milliseconds: 400));
      await gesture.up();
      await t.pumpAndSettle();
      await helper.settle(t);
      await helper.settle(t);
      final preferences = (await t.runAsync(
        () => db.select(db.preferences).get(),
      ))!;
      expect(
        jsonDecode(
          preferences.singleWhere((p) => p.key == 'account_order').value,
        ),
        isNotEmpty,
      );
      await helper.mount(t, db, const AccountsPage());
      final reordered = find.descendant(
        of: find.byType(ReorderableListView).first,
        matching: find.byType(ReorderableDelayedDragStartListener),
      );
      expect(
        t.widget<ReorderableDelayedDragStartListener>(reordered.first).key,
        names[1],
      );
      expect(
        t.widget<ReorderableDelayedDragStartListener>(reordered.at(1)).key,
        names[0],
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(milliseconds: 1));
    },
  );
}
