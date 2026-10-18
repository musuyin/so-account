import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';
import 'package:so_account/features/statistics/data/statistics_repository.dart';
import 'package:so_account/features/statistics/domain/report_range.dart';

void main() {
  late AppDatabase db;
  late LedgerRepository ledger;
  late StatisticsRepository stats;
  late String account;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    ledger = LedgerRepository(db);
    stats = StatisticsRepository(db);
    await ledger.saveAccount(
      name: '测试',
      kind: '资金账户',
      channel: '现金',
      currency: 'CNY',
      openingBalance: 10000,
    );
    account = (await db.select(db.accounts).get()).single.id;
    Future<void> add(
      EntryKind kind,
      int amount,
      String date, {
      String? category,
    }) async {
      await ledger.saveEntry(
        kind: kind,
        amount: amount,
        accountId: account,
        date: date,
        categoryId: kind.needsCategory ? category ?? '${kind.name}-0' : null,
      );
    }

    await add(EntryKind.income, 1000, '2025-10-01');
    await add(EntryKind.expense, 500, '2025-10-02');
    await add(EntryKind.income, 10000, '2026-09-01');
    await add(EntryKind.expense, 4000, '2026-09-05');
    await add(EntryKind.expense, 1000, '2026-09-06', category: 'expense-1');
    await add(EntryKind.income, 20000, '2026-10-01');
    await add(EntryKind.expense, 3000, '2026-10-05');
    await add(EntryKind.expense, 500, '2026-10-06', category: 'expense-2');
    await add(EntryKind.borrow, 5000, '2026-10-03');
    await add(EntryKind.lend, 700, '2026-10-04');
    await ledger.saveAccount(
      name: '美元',
      kind: '资金账户',
      channel: '现金',
      currency: 'USD',
      openingBalance: 999999,
    );
  });
  tearDown(() => db.close());
  test(
    'seven day report includes empty days and exact daily averages',
    () async {
      final report = await stats.load(
        ReportRange.at(ReportPeriod.week, DateTime(2026, 10, 7)),
        'CNY',
      );
      expect(report.points.length, 7);
      expect(report.income, 20000);
      expect(report.expense, 3500);
      expect(report.dailyExpense, 500);
      expect(report.points[1].income, 0);
      expect(report.points[1].expense, 0);
    },
  );
  test(
    'monthly category comparison handles previous zero and favorable direction',
    () async {
      final report = await stats.load(
        ReportRange.at(ReportPeriod.month, DateTime(2026, 10)),
        'CNY',
      );
      expect(report.previousExpense, 5000);
      expect(report.previousIncome, 10000);
      final reduced = report.categories.firstWhere((c) => c.id == 'expense-0');
      expect(reduced.growth, -0.25);
      expect(reduced.improved, isTrue);
      final fresh = report.categories.firstWhere((c) => c.id == 'expense-2');
      expect(fresh.growth, isNull);
      expect(fresh.delta, 500);
      expect(
        report.categories.firstWhere((c) => c.kind == 'income').improved,
        isTrue,
      );
    },
  );
  test('year compares previous year and reconstructs net assets without debt inflation', () async {
    final report = await stats.load(
      ReportRange.at(ReportPeriod.year, DateTime(2026, 10)),
      'CNY',
    );
    expect(report.points.length, 12);
    expect(report.income, 30000);
    expect(report.expense, 8500);
    expect(report.previousIncome, 1000);
    expect(report.previousExpense, 500);
    expect(report.points.first.netAssets, 10500);
    expect(report.points.last.netAssets, 32000);
  });
  test(
    'custom inclusive dates and leap-year month comparison are correct',
    () async {
      final range = ReportRange.at(
        ReportPeriod.custom,
        DateTime(2026, 10, 2),
        customStart: DateTime(2026, 9, 29),
        customEnd: DateTime(2026, 10, 2),
      );
      final report = await stats.load(range, 'CNY');
      expect(range.days, 4);
      expect(report.income, 20000);
      expect(report.expense, 0);
      final march = ReportRange.at(ReportPeriod.month, DateTime(2024, 3));
      expect(march.previous.days, 29);
    },
  );
}
