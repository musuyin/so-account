import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:so_account/app/app.dart';
import 'package:so_account/app/providers/providers.dart';
import 'package:so_account/core/appearance.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/app/theme/app_theme.dart';

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
    await tester.tap(find.text('夏日黄瓜花'));
    await settleData();
    final saved = await tester.runAsync(() => db.select(db.preferences).get());
    expect(
      saved!.any((p) => p.key == 'palette' && p.value == 'cucumber'),
      isTrue,
    );
    final material = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(
      material.theme!.colorScheme.surface,
      appTheme(
        Brightness.light,
        palette: AppPalette.cucumber,
      ).colorScheme.surface,
    );
    await tester.tap(find.text('经典暖白'));
    await settleData();
    expect(
      tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .theme!
          .colorScheme
          .surface,
      appTheme(
        Brightness.light,
        palette: AppPalette.classic,
      ).colorScheme.surface,
    );
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
