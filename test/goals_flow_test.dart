import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/app/providers/providers.dart';
import 'package:so_account/app/theme/app_theme.dart';
import 'package:so_account/core/appearance.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/goals/data/goals_repository.dart';
import 'package:so_account/features/goals/presentation/goals_page.dart';

void main() {
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  Future<void> enter(WidgetTester t, String label, String text) async {
    await t.ensureVisible(field(label));
    await t.enterText(field(label), text);
    await t.pump();
  }

  testWidgets(
    'create, deposit, reject overdraft, withdraw, complete and reopen at phone width',
    (t) async {
      t.view.physicalSize = const Size(320, 820);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => t.runAsync(db.close));
      await t.runAsync(() => db.select(db.wishGoals).get());
      await t.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: appTheme(Brightness.light),
            home: const GoalsPage(),
          ),
        ),
      );
      await settle(t);
      await t.tap(find.text('新增目标'));
      await settle(t);
      await t.tap(find.text('攒钱'));
      await enter(t, '目标名称', '旅行基金');
      await enter(t, '目标金额', '1000');
      await enter(t, '已经攒下（选填）', '100');
      await t.tap(find.text('保存'));
      await settle(t);
      expect(find.text('旅行基金'), findsOneWidget);
      await t.tap(find.text('旅行基金'));
      await settle(t);
      Future<void> contribution(String button, String amount) async {
        await t.ensureVisible(find.text(button));
        await t.tap(find.text(button));
        await settle(t);
        await enter(t, '金额 · CNY', amount);
        await t.tap(find.text('保存'));
        await settle(t);
      }

      await contribution('存入', '300');
      await contribution('取出', '500');
      expect(find.textContaining('取出金额超过已攒金额'), findsOneWidget);
      await enter(t, '金额 · CNY', '50');
      await t.tap(find.text('保存'));
      await settle(t);
      var rows = await t.runAsync(() => db.select(db.goalContributions).get());
      final goals = await t.runAsync(() => db.select(db.wishGoals).get());
      expect(goalSaved(goals!.single.id, rows!), 35000);
      await contribution('存入', '850');
      await t.ensureVisible(find.text('完成攒钱目标'));
      await t.tap(find.text('完成攒钱目标'));
      await settle(t);
      expect(find.text('恢复进行中'), findsOneWidget);
      await t.tap(find.text('恢复进行中'));
      await settle(t);
      expect(find.text('完成攒钱目标'), findsOneWidget);
      expect(await t.runAsync(() => db.select(db.entries).get()), isEmpty);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets('new goal keeps the currency selected on its parent list', (
    t,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => t.runAsync(db.close));
    await t.runAsync(() => db.select(db.wishGoals).get());
    await t.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: GoalsPage(initialCurrency: 'JPY')),
      ),
    );
    await settle(t);
    await t.tap(find.text('新增目标'));
    await settle(t);
    await enter(t, '目标名称', '日元目标');
    await enter(t, '目标金额', '1000');
    await t.tap(find.text('保存'));
    await settle(t);
    final rows = await t.runAsync(() => db.select(db.wishGoals).get());
    expect(rows!.single.currency, 'JPY');
    expect(rows.single.target, 1000);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(milliseconds: 1));
  });
  for (final brightness in Brightness.values) {
    for (final palette in AppPalette.values) {
      testWidgets(
        'goals respect $palette $brightness with large text at 320 pixels',
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
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
          final g = WishGoal(
            id: 'travel',
            name: '下一个旅行目的地',
            kind: 'saving',
            currency: 'CNY',
            target: 100000,
            deadline: '2026-12-31',
            priority: 2,
            status: 'active',
            note: '慢慢积攒',
            createdAt: 0,
            updatedAt: 0,
          );
          final data = AppSnapshot(
            [],
            [],
            [],
            [],
            [],
            [],
            [],
            [],
            [g],
            [
              const GoalContribution(
                id: 'a',
                goalId: 'travel',
                amount: 35000,
                date: '2026-10-23',
                note: '',
                createdAt: 0,
              ),
            ],
          );
          final boundary = GlobalKey();
          await t.pumpWidget(
            ProviderScope(
              overrides: [
                snapshotProvider.overrideWith((ref) => Stream.value(data)),
              ],
              child: MaterialApp(
                theme: appTheme(brightness, palette: palette),
                home: RepaintBoundary(key: boundary, child: const GoalsPage()),
              ),
            ),
          );
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          await t.ensureVisible(find.text('下一个旅行目的地'));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          await t.runAsync(() async {
            await Directory('.tooling/screenshots').create(recursive: true);
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '.tooling/screenshots/goals-${palette.name}-${brightness.name}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
          await t.pumpWidget(const SizedBox.shrink());
          await t.pump();
        },
      );
    }
  }
}
