import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/app/app.dart';
import 'package:so_account/app/providers/providers.dart';
import 'package:so_account/core/time/business_date.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/statistics/data/statistics_repository.dart';
import 'package:so_account/features/statistics/presentation/statistics_page.dart';
import 'package:so_account/platform/media/media_store.dart';

void main() {
  for (final theme in ['light', 'dark']) {
    for (final width in [390.0, 320.0]) {
      testWidgets('phone routes render in $theme mode at $width pixels', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = width == 320
            ? 1.4
            : 1.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await (FontLoader(
          'NotoSansSC',
        )..addFont(rootBundle.load('assets/fonts/NotoSansSC.ttf'))).load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        final now = DateTime.now();
        final month = monthKey(now);
        final data = AppSnapshot(
          [
            const Account(
              id: 'wallet',
              name: '日常钱包',
              kind: '资金账户',
              channel: '微信支付',
              currency: 'CNY',
              openingBalance: 20000,
            ),
          ],
          [const Category(id: 'food', name: '饮食', kind: 'expense')],
          [
            Entry(
              id: 'lunch',
              kind: 'expense',
              amount: 2850,
              accountId: 'wallet',
              date: dateKey(now),
              note: '午饭',
              createdAt: 0,
              updatedAt: 0,
              categoryId: 'food',
            ),
          ],
          [],
          [],
          [],
          [Preference(key: 'theme', value: theme)],
        );
        final boundary = GlobalKey();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              snapshotProvider.overrideWith((ref) => Stream.value(data)),
              balancesProvider.overrideWith(
                (ref) => Stream.value({'wallet': 17150}),
              ),
              monthlyProvider(month).overrideWith(
                (ref) =>
                    Stream.value([const MonthlyTotal('CNY', 'expense', 2850)]),
              ),
              breakdownProvider((month, 'CNY')).overrideWith(
                (ref) => Stream.value([const Breakdown('饮食', 'expense', 2850)]),
              ),
              trendProvider((month, 'CNY')).overrideWith(
                (ref) => Stream.value([Trend(month, 'expense', 2850)]),
              ),
              mediaProvider.overrideWith(
                (ref) async => MediaStore(Directory.systemTemp),
              ),
            ],
            child: RepaintBoundary(key: boundary, child: const SoAccountApp()),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('把日子，记清楚。'), findsOneWidget);
        expect(find.text('-28.50'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('.tooling/screenshots').create(recursive: true);
          await File('.tooling/screenshots/home-$theme.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        for (final label in ['账户', '物品', '统计', '设置']) {
          await tester.tap(find.text(label).last);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: label);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
    }
  }
}
