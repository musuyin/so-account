import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';
import 'package:so_account/features/ledger/domain/asset_summary.dart';
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
  test(
    'current month includes today and excludes later transactions',
    () async {
      final today = DateTime(2026, 10, 5, 23, 45);
      final range = ReportRange.at(
        ReportPeriod.month,
        DateTime(2026, 10, 20),
        today: today,
      );
      final report = await stats.load(range, 'CNY');

      expect(report.income, 20000);
      expect(report.expense, 3000);
      expect(report.dailyExpense, 600);
      expect(report.previousExpense, 5000);
      expect(report.points, hasLength(5));
      expect(report.points.last.label, '2026-10-05');
      expect(report.points.last.expense, 3000);
      expect(report.categories.any((c) => c.id == 'expense-2'), isFalse);
      expect(
        range.intervalFor(report.points.last.label).$2,
        DateTime(2026, 10, 6),
      );

      final historical = ReportRange.at(
        ReportPeriod.month,
        range.start,
        today: DateTime(2026, 11, 1),
      );
      expect(historical.days, 31);
      expect((await stats.load(historical, 'CNY')).expense, 3500);
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
  test(
    'long custom buckets retain exact flows and clamp partial bucket details',
    () async {
      for (final start in [DateTime(2026, 8, 29), DateTime(2026, 1, 15)]) {
        final range = ReportRange.at(
          ReportPeriod.custom,
          DateTime(2026, 10, 6),
          customStart: start,
          customEnd: DateTime(2026, 10, 6),
        );
        final report = await stats.load(range, 'CNY');
        expect(
          report.points.fold<int>(0, (s, p) => s + p.income),
          report.income,
        );
        expect(
          report.points.fold<int>(0, (s, p) => s + p.expense),
          report.expense,
        );
        expect(report.points.length, lessThanOrEqualTo(14));
        expect(range.intervalFor(report.points.first.label).$1, start);
        expect(range.intervalFor(report.points.last.label).$2, range.end);
        expect(report.points.last.netAssets, 32000);
      }
    },
  );
  test(
    'JPY exact amounts and negative surplus exclude debt principal',
    () async {
      final yen = await ledger.saveAccount(
        name: '合成日元',
        kind: '资金账户',
        channel: '现金',
        currency: 'JPY',
        openingBalance: 10000,
      );
      await ledger.saveEntry(
        kind: EntryKind.expense,
        amount: 9999,
        accountId: yen,
        date: '2026-10-01',
        categoryId: 'expense-0',
      );
      await ledger.saveEntry(
        kind: EntryKind.borrow,
        amount: 100000,
        accountId: yen,
        date: '2026-10-01',
      );
      final report = await stats.load(
        ReportRange.at(ReportPeriod.month, DateTime(2026, 10)),
        'JPY',
      );
      expect(report.expense, 9999);
      expect(report.income, 0);
      expect(report.surplus, -9999);
      expect(report.points.first.netAssets, 1);
      expect(report.categories.single.growth, isNull);
    },
  );

  test('net-assets plot follows fixed account ownership and excludes reimbursement', () async {
    Future<String> add(String name, String kind, String channel, int balance) =>
        ledger.saveAccount(
          name: name,
          kind: kind,
          channel: channel,
          currency: 'CNY',
          openingBalance: balance,
        );
    await add('合成信贷盈余', '信贷账户', '信用卡', 2000);
    await add('合成负资金', '资金账户', '现金', -3000);
    await add('合成借入', '债务', '应付款', 4000);
    await add('合成借出', '债务', '应收款', 6000);
    final reimburse = await add('合成报销', '债务', '报销', 50000);
    await ledger.saveEntry(
      kind: EntryKind.transfer,
      amount: 1000,
      accountId: account,
      targetAccountId: reimburse,
      date: '2026-10-10',
    );
    await ledger.saveEntry(
      kind: EntryKind.transfer,
      amount: 500,
      accountId: reimburse,
      targetAccountId: account,
      date: '2026-10-11',
    );
    await ledger.saveEntry(
      kind: EntryKind.reimburse,
      amount: 3000,
      accountId: account,
      date: '2026-10-12',
      counterparty: '合成新报销',
    );
    final report = await stats.load(
      ReportRange.at(ReportPeriod.month, DateTime(2026, 10)),
      'CNY',
    );
    expect(report.income, 20000);
    expect(report.expense, 3500);
    expect(report.points.last.netAssets, 29500);
    final accounts = (await db.select(db.accounts).get()).where(
      (a) => a.currency == 'CNY',
    );
    expect(
      report.points.last.netAssets,
      AssetSummary.calculate(accounts, await ledger.balances()).net,
    );
  });
}
