import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:so_account/features/backup/data/backup_service.dart';
import 'package:so_account/platform/media/media_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:so_account/app/app.dart';
import 'package:so_account/app/providers/providers.dart';
import 'package:so_account/core/appearance.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/app/theme/app_theme.dart';
import 'package:so_account/features/statistics/presentation/report_charts.dart';

void main() {
  test('all day palettes use the same neutral background', () {
    for (final palette in AppPalette.values) {
      expect(
        appTheme(Brightness.light, palette: palette).scaffoldBackgroundColor,
        const Color(0xFFF5F5F5),
      );
    }
  });
  testWidgets('palette selection persists and updates the running app', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(db.close));
    await tester.runAsync(() => db.select(db.preferences).get());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const SoAccountApp(),
      ),
    );
    Future<void> settleData() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
    }

    await settleData();
    await tester.tap(find.text('设置').last);
    await settleData();
    for (final palette in AppPalette.values) {
      await tester.ensureVisible(find.text(palette.label));
      await tester.tap(find.text(palette.label));
      await settleData();
      for (final (label, mode, brightness) in [
        ('浅色', ThemeMode.light, Brightness.light),
        ('深色', ThemeMode.dark, Brightness.dark),
        ('跟随系统', ThemeMode.system, Brightness.light),
      ]) {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await settleData();
        final material = tester.widget<MaterialApp>(find.byType(MaterialApp));
        expect(material.themeMode, mode);
        final pageTheme = Theme.of(tester.element(find.text(label)));
        expect(pageTheme.brightness, brightness);
        expect(
          pageTheme.colorScheme.primary,
          appTheme(brightness, palette: palette).colorScheme.primary,
        );
        expect(pageTheme.cardTheme.shape.runtimeType, RoundedRectangleBorder);
      }
    }
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('跟随系统'))).brightness,
      Brightness.dark,
    );
    await tester.tap(find.text('账本').last);
    await settleData();
    await tester.tap(find.text('设置').last);
    await settleData();
    final saved = await tester.runAsync(() => db.select(db.preferences).get());
    expect(
      saved!.any((p) => p.key == 'palette' && p.value == 'lavender'),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const SoAccountApp(),
      ),
    );
    await settleData();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );
    expect(
      tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .darkTheme!
          .colorScheme
          .primary,
      appTheme(
        Brightness.dark,
        palette: AppPalette.lavender,
      ).colorScheme.primary,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
  testWidgets(
    'theme restore updates running page and a failed write keeps saved selection',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => tester.runAsync(db.close));
      final root = await tester.runAsync(
        () => Directory.systemTemp.createTemp('so-account-theme-'),
      );
      addTearDown(() => tester.runAsync(() => root!.delete(recursive: true)));
      final service = BackupService(db, MediaStore(root!));
      final backup = await tester.runAsync(() async {
        await db.select(db.preferences).get();
        await db
            .into(db.preferences)
            .insertOnConflictUpdate(
              PreferencesCompanion.insert(key: 'palette', value: 'sky'),
            );
        await db
            .into(db.preferences)
            .insertOnConflictUpdate(
              PreferencesCompanion.insert(key: 'theme', value: 'dark'),
            );
        final bytes = await service.export();
        await (db.update(db.preferences)..where((p) => p.key.equals('palette')))
            .write(const PreferencesCompanion(value: Value('classic')));
        return bytes;
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            initialCleanupProvider.overrideWith((ref) async => null),
          ],
          child: const SoAccountApp(),
        ),
      );
      Future<void> settle() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
      }

      await settle();
      await tester.tap(find.text('设置').last);
      await settle();
      await tester.runAsync(() => service.restore(backup!));
      await settle();
      expect(
        tester
            .widget<MaterialApp>(find.byType(MaterialApp))
            .darkTheme!
            .colorScheme
            .primary,
        appTheme(Brightness.dark, palette: AppPalette.sky).colorScheme.primary,
      );
      expect(
        Theme.of(tester.element(find.text('蓝色'))).brightness,
        Brightness.dark,
      );
      await tester.runAsync(
        () => db.customStatement(
          "CREATE TRIGGER reject_palette BEFORE INSERT ON preferences WHEN NEW.key='palette' BEGIN SELECT RAISE(ABORT,'synthetic write failure'); END",
        ),
      );
      await tester.ensureVisible(find.text('绿色'));
      await tester.tap(find.text('绿色'));
      await settle();
      expect(find.textContaining('操作失败'), findsOneWidget);
      final saved = await tester.runAsync(
        () => db.select(db.preferences).get(),
      );
      expect(saved!.firstWhere((p) => p.key == 'palette').value, 'sky');
      expect(
        tester
            .widget<MaterialApp>(find.byType(MaterialApp))
            .darkTheme!
            .colorScheme
            .primary,
        appTheme(Brightness.dark, palette: AppPalette.sky).colorScheme.primary,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );
  testWidgets('asset privacy follows navigation into the statistics plot', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(db.close));
    await tester.runAsync(() => db.select(db.preferences).get());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const SoAccountApp(),
      ),
    );
    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
    }

    await settle();
    await tester.tap(find.text('账户').last);
    await settle();
    await tester.tap(find.byTooltip('隐藏金额'));
    await settle();
    await tester.tap(find.text('统计').last);
    await settle();
    await tester.tap(find.widgetWithText(ChoiceChip, '年'));
    await settle();
    await tester.scrollUntilVisible(
      find.text('资产金额已隐藏'),
      500,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 50,
    );
    expect(find.byType(AssetLine), findsNothing);
    await tester.ensureVisible(find.text('显示资产金额'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('显示资产金额'));
    await settle();
    expect(find.byType(AssetLine), findsOneWidget);
    await tester.tap(find.text('账户').last);
    await settle();
    expect(find.byTooltip('隐藏金额'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
  testWidgets('warm and dark themes render', (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(brightness),
          home: const Scaffold(body: Text('素帐')),
        ),
      );
      expect(find.text('素帐'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
