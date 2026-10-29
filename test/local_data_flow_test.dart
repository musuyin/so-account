import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/app/app.dart';
import 'package:so_account/app/providers/providers.dart';
import 'package:so_account/data/category_settings_store.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/settings/data/local_data_service.dart';
import 'package:so_account/features/settings/presentation/local_data_page.dart';
import 'package:so_account/features/updates/presentation/update_controller.dart';

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 400; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await t.pump(const Duration(milliseconds: 50));
    if (!t.binding.hasScheduledFrame) return;
  }
  await t.pumpAndSettle();
}

Finder button(String title) => find.widgetWithText(OutlinedButton, title);
final confirmation = find.byKey(const ValueKey('local-data-confirmation'));

Future<void> show(WidgetTester t, Finder target) async {
  await Scrollable.ensureVisible(t.element(target), alignment: .45);
  await t.pumpAndSettle();
}

Future<void> enterManagement(WidgetTester t) async {
  await t.tap(find.text('设置').last);
  await settle(t);
  await t.scrollUntilVisible(
    find.text('数据管理'),
    280,
    scrollable: find.byType(Scrollable).first,
  );
  await t.ensureVisible(find.text('数据管理'));
  await t.pumpAndSettle();
  await t.tap(find.text('数据管理'));
  await t.pumpAndSettle();
  expect(find.byType(NavigationBar), findsNothing);
}

void main() {
  late AppDatabase db;
  late Directory root, support, cache;
  late LocalDataService service;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('so_reset_ui_');
    support = await Directory('${root.path}/support').create();
    cache = await Directory('${root.path}/cache').create();
    db = AppDatabase(NativeDatabase.memory());
    await LedgerRepository(db).saveAccount(
      name: '合成账户',
      kind: '资金账户',
      channel: '现金',
      currency: 'CNY',
      openingBalance: 100,
    );
    await LedgerRepository(db)
        .saveCategory('普通餐饮', 'expense', iconId: 'restaurant');
    await db
        .into(db.preferences)
        .insertOnConflictUpdate(
          PreferencesCompanion.insert(key: 'palette', value: 'lavender'),
        );
    await Directory('${support.path}/media').create();
    await File('${support.path}/media/synthetic.jpg').writeAsBytes([1]);
    await File('${cache.path}/shared.csv').writeAsBytes([2]);
    service = LocalDataService(
      db,
      paths: () async => LocalDataPaths(support, cache),
    );
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  Future<void> open(
    WidgetTester t, {
    GlobalKey? boundary,
    LocalDataService? override,
  }) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          localDataServiceProvider.overrideWithValue(override ?? service),
        ],
        child: boundary == null
            ? const SoAccountApp()
            : RepaintBoundary(key: boundary, child: const SoAccountApp()),
      ),
    );
    await settle(t);
  }

  Future<void> dispose(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(milliseconds: 1));
  }

  testWidgets(
    'cancel, barrier dismissal and incorrect confirmation never delete data',
    (t) async {
      await open(t);
      await enterManagement(t);
      for (final title in ['清空本地数据', '重置软件']) {
        await show(t, button(title));
        await t.tap(button(title));
        await t.pumpAndSettle();
        final confirm = find.widgetWithText(
          FilledButton,
          title == '重置软件' ? '确认重置' : '确认清空',
        );
        expect(t.widget<FilledButton>(confirm).onPressed, isNull);
        await t.enterText(confirmation, '错误确认');
        await t.pump();
        expect(t.widget<FilledButton>(confirm).onPressed, isNull);
        await t.enterText(confirmation, title == '重置软件' ? '重置软件' : '清空数据');
        await t.pump();
        expect(t.widget<FilledButton>(confirm).onPressed, isNotNull);
        await t.tap(find.text('取消'));
        await t.pumpAndSettle();
        expect(
          (await t.runAsync(() => db.select(db.accounts).get()))!.single.name,
          '合成账户',
        );
        expect(
          await t.runAsync(
            () => File('${support.path}/media/synthetic.jpg').exists(),
          ),
          isTrue,
        );
      }
      await show(t, button('清空本地数据'));
      await t.tap(button('清空本地数据'));
      await t.pumpAndSettle();
      await t.tapAt(const Offset(4, 4));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        await t.runAsync(() => db.select(db.accounts).get()),
        hasLength(1),
      );
      await dispose(t);
    },
  );

  for (final reset in [false, true]) {
    testWidgets(
      'confirmed ${reset ? 'reset' : 'clear'} refreshes app session and categories correctly',
      (t) async {
        await open(t);
        await enterManagement(t);
        await show(t, button(reset ? '重置软件' : '清空本地数据'));
        await t.tap(button(reset ? '重置软件' : '清空本地数据'));
        await t.pumpAndSettle();
        await t.enterText(confirmation, reset ? '重置软件' : '清空数据');
        await t.pump();
        await t.tap(find.text(reset ? '确认重置' : '确认清空'));
        await settle(t);
        await settle(t);
        expect(t.takeException(), isNull);
        expect(find.byType(LocalDataPage), findsNothing);
        expect(await t.runAsync(() => db.select(db.accounts).get()), isEmpty);
        final categories = await t.runAsync(
          () => db.select(db.categories).get(),
        );
        expect(categories!.any((c) => c.name == '普通餐饮'), !reset);
        expect(
          await t.runAsync(() => CategorySettingsStore(db).read('palette')),
          reset ? isNull : 'lavender',
        );
        expect(
          await t.runAsync(
            () => File('${support.path}/media/synthetic.jpg').exists(),
          ),
          isFalse,
        );
        expect(
          await t.runAsync(() => File('${cache.path}/shared.csv').exists()),
          isFalse,
        );
        await dispose(t);
      },
    );
  }

  testWidgets('interrupted cleanup blocks startup until retry finishes', (
    t,
  ) async {
    var fail = true;
    final failing = LocalDataService(
      db,
      paths: () async => LocalDataPaths(support, cache),
      deleteFile: (entity) async {
        if (fail) throw const FileSystemException('simulated failure');
        await entity.delete();
      },
    );
    await t.runAsync(
      () => expectLater(
        failing.execute(LocalDataAction.resetApp),
        throwsA(isA<LocalCleanupException>()),
      ),
    );
    await open(t, override: failing);
    expect(find.textContaining('上次本地数据删除尚未完成'), findsOneWidget);
    expect(find.text('账本'), findsNothing);
    fail = false;
    await t.tap(find.text('重试清理'));
    await settle(t);
    await settle(t);
    expect(find.text('账本'), findsOneWidget);
    expect(
      await t.runAsync(() => CategorySettingsStore(db).read(localCleanupKey)),
      isNull,
    );
    await dispose(t);
  });

  testWidgets(
    'update maintenance preserves automatic preference for clear and resets it for full reset',
    (t) async {
      await t.runAsync(() async {
        final updates = UpdateController();
        await updates.initialize();
        await updates.setAutomatic(false);
        await updates.pauseForDataMaintenance();
        await updates.setAutomatic(true);
        expect(updates.automatic, isFalse);
        updates.finishDataMaintenance(resetSettings: false);
        expect(updates.automatic, isFalse);
        await updates.pauseForDataMaintenance();
        updates.finishDataMaintenance(resetSettings: true);
        expect(updates.automatic, isTrue);
        updates.dispose();
      });
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'data actions and confirmation render at 320px large text dark=$dark',
      (t) async {
        t.view.physicalSize = const Size(320, 844);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = 1.6;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await (FontLoader(
          'NotoSansSC',
        )..addFont(rootBundle.load('assets/fonts/NotoSansSC.ttf'))).load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        await t.runAsync(
          () => db
              .into(db.preferences)
              .insertOnConflictUpdate(
                PreferencesCompanion.insert(
                  key: 'theme',
                  value: dark ? 'dark' : 'light',
                ),
              ),
        );
        final boundary = GlobalKey();
        await open(t, boundary: boundary);
        expect(
          t.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
          dark ? ThemeMode.dark : ThemeMode.light,
        );
        await enterManagement(t);
        Future<void> screenshot(String name) async {
          expect(t.takeException(), isNull);
          await t.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory('.tooling/screenshots').create(recursive: true);
            await File(
              '.tooling/screenshots/local-data-$name-${dark ? 'dark' : 'light'}-320.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await screenshot('actions');
        await show(t, button('重置软件'));
        await t.tap(button('重置软件'));
        await t.pumpAndSettle();
        await screenshot('confirm');
        await dispose(t);
      },
    );
  }
}
