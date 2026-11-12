import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/features/goals/data/goals_repository.dart';
import 'package:so_account/features/goals/presentation/goals_page.dart';
import 'package:so_account/features/ledger/presentation/amount_pad.dart';
import 'package:so_account/features/ledger/presentation/entry_form.dart';

import 'exposed_accounts_ui_test.dart' as helper;

void main() {
  testWidgets(
    'amount action calculates before saving and tracks external edits',
    (t) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var saves = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AmountPad(
              controller: controller,
              currency: 'CNY',
              onSave: () => saves++,
            ),
          ),
        ),
      );
      expect(find.text('='), findsNothing);
      for (final key in ['1', '+', '2', '×', '3']) {
        await t.tap(find.text(key));
        await t.pump();
      }
      expect(find.text('保存'), findsNothing);
      expect(find.text('='), findsOneWidget);
      expect(
        t.widget<TextField>(find.byType(TextField)).decoration!.suffixIcon,
        isNull,
      );
      await t.tap(find.text('='));
      await t.pump();
      expect(controller.text, '7.00');
      expect(saves, 0);
      await t.tap(find.text('保存'));
      expect(saves, 1);
      for (final expression in ['1+', '1÷0', '1-2']) {
        controller.text = expression;
        await t.pump();
        await t.tap(find.text('='));
        await t.pump();
        expect(controller.text, expression);
        expect(find.text('保存'), findsNothing);
        expect(saves, 1);
      }
      controller.text = '1+';
      await t.pump();
      await t.tap(find.byIcon(Icons.backspace_outlined));
      await t.pump();
      expect(find.text('保存'), findsOneWidget);
      controller.text = '1+2';
      await t.pump();
      await t.longPress(find.byIcon(Icons.backspace_outlined));
      await t.pump();
      expect(controller.text, isEmpty);
      expect(find.text('='), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'unified form and amount action at 320px large text $brightness',
      (t) async {
        t.view.physicalSize = const Size(320, 950);
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
        final boundary = GlobalKey();
        final id = await t.runAsync(
          () => GoalsRepository(db).save(
            name: '旧攒钱目标',
            kind: 'saving',
            currency: 'CNY',
            target: 1000000,
            initialSaved: 250000,
          ),
        );
        await helper.mount(
          t,
          db,
          const GoalsPage(),
          brightness: brightness,
          boundary: boundary,
        );
        expect(find.text('全部类型'), findsNothing);
        await t.tap(find.text('新增目标'));
        await helper.settle(t);
        expect(find.text('攒钱'), findsNothing);
        await t.enterText(helper.field('目标名称'), '要攒10000元');
        await t.enterText(helper.field('目标金额'), '10000');
        await t.ensureVisible(helper.field('已经攒下（选填）'));
        await t.enterText(helper.field('已经攒下（选填）'), '2500');
        await t.ensureVisible(find.widgetWithText(ChoiceChip, '优先'));
        await t.tap(find.widgetWithText(ChoiceChip, '优先'));
        t.testTextInput.hide();
        await t.pumpAndSettle();
        await helper.capture(
          t,
          boundary,
          'unified-goal-form-${brightness.name}',
        );
        await t.tap(find.text('保存'));
        await helper.settle(t);
        final goals = await t.runAsync(() => db.select(db.wishGoals).get());
        final created = goals!.singleWhere((g) => g.name == '要攒10000元');
        expect(created.target, 1000000);
        expect(created.priority, 2);
        final records = await t.runAsync(
          () => db.select(db.goalContributions).get(),
        );
        expect(goalSaved(created.id, records!), 250000);
        await t.tap(find.text('旧攒钱目标'));
        await helper.settle(t);
        await t.tap(find.byTooltip('编辑目标'));
        await helper.settle(t);
        expect(
          t
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'USD'))
              .onSelected,
          isNull,
        );
        await t.enterText(helper.field('目标名称'), '取消的修改');
        await t.tap(find.byType(BackButton));
        await helper.settle(t);
        expect(find.text('旧攒钱目标'), findsOneWidget);
        await t.ensureVisible(find.text('标记已实现'));
        await t.tap(find.text('标记已实现'));
        await helper.settle(t);
        final updated = await t.runAsync(() => db.select(db.wishGoals).get());
        expect(updated!.singleWhere((g) => g.id == id).status, 'completed');
        expect(goalSaved(id!, records), 250000);
        await helper.mount(
          t,
          db,
          const EntryForm(),
          brightness: brightness,
          boundary: boundary,
        );
        for (final key in ['1', '+', '2']) {
          await t.tap(find.text(key));
          await t.pump();
        }
        await helper.capture(t, boundary, 'amount-equals-${brightness.name}');
        await t.tap(find.text('='));
        await t.pumpAndSettle();
        expect(find.text('='), findsNothing);
        expect(find.text('保存'), findsOneWidget);
        expect(t.takeException(), isNull);
        await helper.capture(t, boundary, 'amount-save-${brightness.name}');
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(milliseconds: 1));
      },
    );
  }
}
