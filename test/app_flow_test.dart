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
import 'package:so_account/features/statistics/domain/report_range.dart';
import 'package:so_account/features/statistics/presentation/statistics_page.dart';
import 'package:so_account/platform/media/media_store.dart';

void main() {
  for (final theme in ['light', 'dark', 'cucumber-light', 'cucumber-dark']) {
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
              isArchived: false,
              bank: '',
              customChannel: '',
              id: 'wallet',
              avatar: '',
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
              counterparty: '',
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
          [
            Preference(
              key: 'theme',
              value: theme.endsWith('dark') ? 'dark' : 'light',
            ),
            Preference(
              key: 'palette',
              value: theme.startsWith('cucumber') ? 'cucumber' : 'classic',
            ),
          ],
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
              for (final period in ReportPeriod.values)
                reportProvider((
                  period.name,
                  dateKey(ReportRange.at(period, now).start),
                  dateKey(ReportRange.at(period, now).end),
                  'CNY',
                )).overrideWith((ref) {
                  final range = ReportRange.at(period, now);
                  return Stream.value(
                    FinanceReport(
                      range: range,
                      income: 10000,
                      expense: 2850,
                      previousIncome: 5000,
                      previousExpense: 1000,
                      categories: const [
                        CategoryComparison(
                          'food',
                          '普通餐饮',
                          'expense',
                          2850,
                          1000,
                        ),
                        CategoryComparison(
                          'salary',
                          '工资',
                          'income',
                          10000,
                          5000,
                        ),
                      ],
                      points: range.buckets
                          .map((label) => ReportPoint(label, 100, 50, 20000))
                          .toList(),
                    ),
                  );
                }),
              mediaProvider.overrideWith(
                (ref) async => MediaStore(Directory.systemTemp),
              ),
            ],
            child: RepaintBoundary(key: boundary, child: const SoAccountApp()),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('素帐'), findsOneWidget);
        expect(find.text('-28.50'), findsAtLeastNWidgets(1));
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('.tooling/screenshots').create(recursive: true);
          await File('.tooling/screenshots/home-$theme-${width.toInt()}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        for (final label in ['账户', '物品', '统计', '设置']) {
          await tester.tap(find.text(label).last);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: label);
          if (width == 390) {
            await tester.runAsync(() async {
              final image =
                  await (boundary.currentContext!.findRenderObject()
                          as RenderRepaintBoundary)
                      .toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File('.tooling/screenshots/$label-$theme.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          if (label == '统计') {
            for (final periodLabel in ['周', '年', '自定义', '月']) {
              await tester.tap(find.text(periodLabel).first);
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull, reason: periodLabel);
            }
          }
        }
        await tester.tap(find.text('账本').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('记一笔').last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'entry form');
        expect(find.text('发生日期'), findsNothing);
        expect(
          tester.getTopLeft(find.text('日期')).dy,
          lessThan(tester.getTopLeft(find.text('7').first).dy),
        );
        for (final key in ['7', '+', '2']) {
          await tester.ensureVisible(find.text(key).first);
          await tester.tap(find.text(key).first);
          await tester.pump();
        }
        await tester.ensureVisible(find.text('='));
        await tester.tap(find.text('='));
        await tester.pump();
        expect(find.text('9.00'), findsOneWidget);
        await tester.tap(find.byType(BackButton).first);
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
    }
  }
}
