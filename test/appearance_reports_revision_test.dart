import 'package:drift/drift.dart' hide Column, isNull;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/app/theme/app_theme.dart';
import 'package:so_account/app/theme/app_typography.dart';
import 'package:so_account/core/time/business_date.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/ledger/presentation/calendar_heatmap.dart';
import 'package:so_account/features/ledger/presentation/home_page.dart';
import 'package:so_account/features/statistics/presentation/statistics_page.dart';
import 'package:so_account/features/statistics/presentation/report_charts.dart';
import 'package:so_account/features/statistics/presentation/report_records_page.dart';
import 'package:so_account/features/statistics/data/statistics_repository.dart';

import 'exposed_accounts_ui_test.dart' as helper;

Future<void> scroll(WidgetTester t, Finder finder, double delta) =>
    t.scrollUntilVisible(
      finder,
      delta,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 100,
    );

void main() {
  setUp(() async {
    await (FontLoader(
      'NotoSansSC',
    )..addFont(rootBundle.load('assets/fonts/NotoSansSC.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets(
    'loaded Noto font keeps tabular digits and full large compact amounts',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          theme: appTheme(Brightness.light),
          home: const Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('1111.11', style: AppTypography.amount),
                Text('8888.88', style: AppTypography.amount),
              ],
            ),
          ),
        ),
      );
      expect(
        t.getSize(find.text('1111.11')).width,
        closeTo(t.getSize(find.text('8888.88')).width, .01),
      );
      expect(calendarMoney(999999, 'CNY'), '9999.99');
      expect(calendarMoney(999999999999, 'CNY'), '100.0亿');
      final today = dateKey(DateTime.now());
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LedgerCalendar(
              month: DateTime(DateTime.now().year, DateTime.now().month),
              currency: 'CNY',
              daily: const {},
              selected: today,
              onSelected: (_) {},
            ),
          ),
        ),
      );
      final cell = t.widget<Semantics>(find.byKey(ValueKey('calendar-$today')));
      expect(cell.properties.selected, isTrue);
      expect(cell.properties.label, contains('今天'));
      expect(
        find.descendant(
          of: find.byKey(ValueKey('calendar-$today')),
          matching: find.byIcon(Icons.circle),
        ),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'seven visible calendar columns keep full amounts and distinct today selection',
    (t) async {
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetPhysicalSize);
      await (FontLoader(
        'NotoSansSC',
      )..addFont(rootBundle.load('assets/fonts/NotoSansSC.ttf'))).load();
      final boundary = GlobalKey();
      for (final width in [320.0, 360.0, 390.0]) {
        for (final scale in [1.0, 1.3, 1.5, 2.0]) {
          for (final brightness in Brightness.values) {
            t.view.physicalSize = Size(width, 900);
            await t.pumpWidget(
              MaterialApp(
                theme: appTheme(brightness),
                home: RepaintBoundary(
                  key: boundary,
                  child: Scaffold(
                    body: MediaQuery(
                      data: MediaQueryData(
                        textScaler: TextScaler.linear(scale),
                      ),
                      child: LedgerCalendar(
                        month: DateTime(2024, 2),
                        currency: 'CNY',
                        daily: const {
                          '2024-02-01': {'income': 800, 'expense': 999999},
                          '2024-02-02': {'expense': 68050},
                          '2024-02-03': {
                            'expense': 10000000,
                            'income': 10000000,
                          },
                        },
                        selected: '2024-02-01',
                        onSelected: (_) {},
                      ),
                    ),
                  ),
                ),
              ),
            );
            await t.pumpAndSettle();
            expect(
              t.takeException(),
              isNull,
              reason: '$width/$scale/$brightness',
            );
            final size = t.getSize(
              find.byKey(const ValueKey('calendar-2024-02-01')),
            );
            expect(size.width, closeTo(width / 7, .01));
            expect(size.height, greaterThanOrEqualTo(size.width - 4));
            expect(find.byType(SingleChildScrollView), findsNothing);
            final sunday = t.getRect(find.text('日'));
            expect(sunday.right, lessThanOrEqualTo(width));
            expect(
              find.byKey(const ValueKey('calendar-2024-02-29')),
              findsOneWidget,
            );
            final cell = t.widget<Semantics>(
              find.byKey(const ValueKey('calendar-2024-02-01')),
            );
            expect(cell.properties.label, contains('支出 9999.99'));
            if (width == 320 && scale == 2) {
              await helper.capture(
                t,
                boundary,
                'v170-calendar-${brightness.name}-320-2x',
              );
            }
          }
        }
      }
      for (final month in [
        DateTime(2021, 2),
        DateTime(2026, 3),
        DateTime(2026, 12),
        DateTime(2027, 1),
      ]) {
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LedgerCalendar(
                month: month,
                currency: 'JPY',
                daily: const {},
                selected: null,
                onSelected: (_) {},
              ),
            ),
          ),
        );
        expect(
          find.byKey(
            ValueKey(
              'calendar-${dateKey(DateTime(month.year, month.month + 1, 0))}',
            ),
          ),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'date groups merge pages and react to edits and deleting the last row',
    (t) async {
      t.view.physicalSize = const Size(390, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final db = await helper.seed(t);
      final today = dateKey(DateTime.now());
      await t.runAsync(() async {
        await db.delete(db.entries).go();
        final wallet = (await db.select(db.accounts).get()).first;
        await db.batch(
          (b) => b.insertAll(db.entries, [
            for (var i = 0; i < 105; i++)
              EntriesCompanion.insert(
                id: 'group-$i',
                kind: 'expense',
                amount: 100,
                accountId: wallet.id,
                categoryId: const Value('expense-0'),
                date: today,
                createdAt: i,
                updatedAt: i,
              ),
          ]),
        );
      });
      await helper.mount(t, db, const HomePage());
      final boundary = GlobalKey();
      await helper.mount(t, db, const HomePage(), boundary: boundary);
      await t.tap(find.byTooltip('收起月历'));
      await helper.settle(t);
      await scroll(t, find.byType(EntryDayCard), 300);
      expect(
        t
            .widgetList<EntryDayCard>(find.byType(EntryDayCard))
            .single
            .totals['expense'],
        10500,
      );
      expect(
        t
            .widgetList<EntryDayCard>(find.byType(EntryDayCard))
            .single
            .entries
            .length,
        100,
      );
      await helper.capture(t, boundary, 'v160-date-group');
      await scroll(t, find.text('显示更多记录'), 1000);
      await t.tap(find.text('显示更多记录'));
      await helper.settle(t);
      expect(
        t
            .widgetList<EntryDayCard>(find.byType(EntryDayCard))
            .single
            .entries
            .length,
        105,
      );
      final moved = dateKey(
        DateTime(
          DateTime.now().year,
          DateTime.now().month,
          DateTime.now().day == 1 ? 2 : 1,
        ),
      );
      await t.runAsync(
        () => (db.update(db.entries)..where((e) => e.id.equals('group-0')))
            .write(EntriesCompanion(date: Value(moved))),
      );
      await helper.settle(t);
      await scroll(t, find.byKey(ValueKey('day-group-$moved')), 300);
      expect(t.widgetList<EntryDayCard>(find.byType(EntryDayCard)).length, 2);
      await t.runAsync(
        () =>
            (db.delete(db.entries)..where((e) => e.id.equals('group-0'))).go(),
      );
      await helper.settle(t);
      expect(t.widgetList<EntryDayCard>(find.byType(EntryDayCard)).length, 1);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(milliseconds: 1));
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'statistics selection drills into exact rows and preserves chart choices $brightness',
      (t) async {
        t.view.physicalSize = const Size(320, 1000);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final db = await helper.seed(t);
        final boundary = GlobalKey();
        await helper.mount(
          t,
          db,
          const StatisticsPage(),
          brightness: brightness,
          boundary: boundary,
        );
        await scroll(t, find.widgetWithText(ChoiceChip, '折线图'), 300);
        await t.tap(find.widgetWithText(ChoiceChip, '折线图'));
        await t.pumpAndSettle();
        await t.tap(find.widgetWithText(ChoiceChip, '结余'));
        await t.pumpAndSettle();
        final chart = find.byKey(const ValueKey('flow-chart')).first;
        await t.ensureVisible(chart);
        final points = t
            .widgetList<FlowBars>(find.byType(FlowBars))
            .first
            .points;
        final index = points.indexWhere((p) => p.expense > 0);
        await t.tapAt(
          t.getTopLeft(chart) +
              Offset(t.getSize(chart).width / points.length * (index + .5), 80),
        );
        await t.pumpAndSettle();
        await t.ensureVisible(find.widgetWithText(TextButton, '查看记录'));
        await helper.capture(
          t,
          boundary,
          'v160-trend-${brightness.name}-320-2x',
        );
        await t.tap(find.widgetWithText(TextButton, '查看记录'));
        await helper.settle(t);
        expect(find.byType(ReportRecordsPage), findsOneWidget);
        final page = t.widget<ReportRecordsPage>(
          find.byType(ReportRecordsPage),
        );
        final selected = await t.runAsync(
          () =>
              (db.select(db.entries)
                    ..where(
                      (e) =>
                          e.date.isBiggerOrEqualValue(page.start) &
                          e.date.isSmallerThanValue(page.end) &
                          e.kind.isIn(['income', 'expense']),
                    )
                    ..orderBy([(e) => OrderingTerm.desc(e.date)]))
                  .get(),
        );
        expect(find.text('共 ${selected!.length} 笔'), findsOneWidget);
        expect(find.text('仅收入与支出'), findsOneWidget);
        Navigator.of(t.element(find.byType(ReportRecordsPage))).pop();
        await helper.settle(t);
        expect(
          t.widgetList<FlowBars>(find.byType(FlowBars)).first.line,
          isTrue,
        );
        expect(
          t.widgetList<FlowBars>(find.byType(FlowBars)).first.metric,
          FlowMetric.surplus,
        );
        await scroll(t, find.widgetWithText(ChoiceChip, '条形排名'), 300);
        await t.tap(find.widgetWithText(ChoiceChip, '条形排名'));
        await t.pumpAndSettle();
        await helper.capture(
          t,
          boundary,
          'v160-ranking-${brightness.name}-320-2x',
        );
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(milliseconds: 1));
      },
    );
  }

  testWidgets(
    'category grouping retains stable colors and expands other categories',
    (t) async {
      final categories = [
        for (var i = 0; i < 9; i++)
          CategoryComparison('id$i', '合成分类$i', 'expense', (i + 1) * 100, 0),
      ];
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CategoryPie(categories: categories, currency: 'JPY'),
            ),
          ),
        ),
      );
      expect(find.text('其他'), findsOneWidget);
      expect(find.text('合成分类0'), findsNothing);
      final before = categoryColor('id0', Brightness.light);
      await t.ensureVisible(find.text('展开全部分类'));
      await t.tap(find.text('展开全部分类'));
      await t.pumpAndSettle();
      expect(find.text('合成分类0'), findsOneWidget);
      expect(categoryColor('id0', Brightness.light), before);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(milliseconds: 1));
    },
  );
}
