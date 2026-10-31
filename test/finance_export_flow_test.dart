import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/app/providers/providers.dart';
import 'package:so_account/app/theme/app_theme.dart';
import 'package:so_account/core/appearance.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';
import 'package:so_account/features/statistics/presentation/finance_export_page.dart';
import 'package:so_account/platform/files/file_delivery.dart';

import 'exposed_accounts_ui_test.dart' as helper;

class _Delivery extends FileDelivery {
  bool saved = true, fail = false;
  String? name;
  Uint8List? bytes;
  int shares = 0;
  @override
  Future<bool> save(String name, Uint8List bytes) async {
    if (fail) throw const FormatException('合成保存失败');
    this.name = name;
    this.bytes = bytes;
    return saved;
  }

  @override
  Future<void> share(String name, Uint8List bytes, Rect origin) async {
    this.name = name;
    this.bytes = bytes;
    shares++;
    expect(origin.isEmpty, isFalse);
  }
}

Future<void> _mount(
  WidgetTester t,
  AppDatabase db,
  _Delivery delivery, {
  GlobalKey? boundary,
}) async {
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        fileDeliveryProvider.overrideWithValue(delivery),
      ],
      child: MaterialApp(
        builder: boundary == null
            ? null
            : (context, child) => RepaintBoundary(key: boundary, child: child),
        theme: appTheme(Brightness.light),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('zh', 'CN')],
        locale: const Locale('zh', 'CN'),
        home: ExportPage(initialMonth: DateTime(2026, 10)),
      ),
    ),
  );
  await helper.settle(t);
}

Future<void> _waitExport(WidgetTester t) async {
  // Let the real encoder isolate finish before settling the animated indicator.
  for (var i = 0; i < 100; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await t.pump();
    if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
  }
  expect(find.byType(LinearProgressIndicator), findsNothing);
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'copy includes notes, current month/currency, fresh data and privacy; preview can close',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await (FontLoader(
        'NotoSansSC',
      )..addFont(rootBundle.load('assets/fonts/NotoSansSC.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => t.runAsync(db.close));
      await t.runAsync(() async {
        final ledger = LedgerRepository(db);
        final cash = await ledger.saveAccount(
          name: '合成钱包',
          kind: '资金账户',
          channel: '现金',
          currency: 'CNY',
          openingBalance: 12345,
        );
        await ledger.saveEntry(
          kind: EntryKind.income,
          amount: 54321,
          accountId: cash,
          categoryId: 'income-0',
          date: '2026-10-01',
        );
      });
      String copied = '';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final boundary = GlobalKey();
      await _mount(t, db, _Delivery(), boundary: boundary);
      await t.enterText(find.byType(TextField), '合成特殊说明\n第二行');
      await t.tap(find.text('复制 Markdown'));
      await helper.settle(t);
      expect(copied, contains('2026-10 月度总结'));
      expect(copied, contains('| 总收入 | 543.21 | 0.00 | NULL |'));
      expect(copied, endsWith('合成特殊说明\n第二行\n'));
      // A live edit invalidates the report instead of reusing a stale export.
      await t.runAsync(
        () => LedgerRepository(db).saveCategory('合成新分类', 'expense'),
      );
      await helper.settle(t);
      await t.tap(find.text('复制 Markdown'));
      await helper.settle(t);
      expect(copied, contains('合成新分类'));
      await t.tap(find.byTooltip('隐藏资产金额'));
      await t.tap(find.text('复制 Markdown'));
      await helper.settle(t);
      expect(copied, contains('| 总资产 | •••• | •••• | •••• |'));
      expect(copied, isNot(contains('666.66')));
      await t.tap(find.text('预览总结'));
      await helper.settle(t);
      expect(find.byType(SelectableText), findsOneWidget);
      expect(
        t.widget<SelectableText>(find.byType(SelectableText)).data,
        contains('••••'),
      );
      await helper.capture(t, boundary, 'export-markdown-preview-hidden');
      Navigator.of(t.element(find.byType(SelectableText))).pop();
      await helper.settle(t);
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        '合成特殊说明\n第二行',
      );
      await t.tap(find.byTooltip('上一期'));
      await helper.settle(t);
      await t.tap(find.text('JPY'));
      await helper.settle(t);
      await t.tap(find.text('复制 Markdown'));
      await helper.settle(t);
      expect(copied, contains('2026-09 月度总结'));
      expect(copied, contains('币种：JPY'));
      expect(copied, contains('| 总收入 | 0 | 0 | 0.00% |'));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets(
    'Excel save cancellation, retry, share, scope and privacy controls',
    (t) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => t.runAsync(db.close));
      final delivery = _Delivery()..saved = false;
      await _mount(t, db, delivery);
      await t.tap(find.text('Excel 汇总'));
      await helper.settle(t);
      Future<void> save() async {
        await t.tap(find.text('保存 Excel'));
        await _waitExport(t);
      }

      await save();
      expect(delivery.name, 'so-account-finance-2026-CNY.xlsx');
      expect(delivery.bytes!.take(2), [80, 75]);
      expect(find.text('已保存 Excel 汇总'), findsNothing);
      delivery.fail = true;
      await save();
      expect(find.text('合成保存失败'), findsOneWidget);
      delivery.fail = false;
      delivery.saved = true;
      await t.tap(find.text('指定月份'));
      await helper.settle(t);
      await save();
      expect(delivery.name, 'so-account-finance-2026-10-CNY.xlsx');
      expect(find.text('已保存 Excel 汇总'), findsOneWidget);
      await t.tap(find.text('全部历史'));
      await t.tap(find.text('分享 Excel'));
      await _waitExport(t);
      expect(delivery.shares, 1);
      expect(delivery.name, 'so-account-finance-all-CNY.xlsx');
      await helper.settle(t);
      await t.tap(find.byTooltip('隐藏资产金额'));
      await helper.settle(t);
      expect(
        t
            .widget<FilledButton>(find.widgetWithText(FilledButton, '保存 Excel'))
            .onPressed,
        isNull,
      );
      expect(
        t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, '分享 Excel'),
            )
            .onPressed,
        isNull,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(milliseconds: 1));
    },
  );

  for (final palette in AppPalette.values) {
    testWidgets(
      'export renders ${palette.name}, light/dark, narrow/large fonts',
      (t) async {
        t.view.devicePixelRatio = 1;
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
        for (final brightness in Brightness.values) {
          for (final width in [390.0, 320.0]) {
            t.view.physicalSize = Size(width, 844);
            t.platformDispatcher.textScaleFactorTestValue = width == 320
                ? 1.6
                : 1;
            await helper.mount(
              t,
              db,
              const ExportPage(),
              palette: palette,
              brightness: brightness,
              boundary: boundary,
            );
            await helper.capture(
              t,
              boundary,
              'export-${palette.name}-${brightness.name}-${width.toInt()}',
            );
            await helper.show(t, find.text('复制 Markdown'));
            expect(t.takeException(), isNull);
            await helper.show(t, find.text('Excel 汇总'));
            await t.tap(find.text('Excel 汇总'));
            await helper.settle(t);
            await helper.capture(
              t,
              boundary,
              'export-excel-${palette.name}-${brightness.name}-${width.toInt()}',
            );
            await helper.show(t, find.text('保存 Excel'));
            expect(t.takeException(), isNull);
          }
        }
      },
    );
  }
}
