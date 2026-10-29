import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/core/recent_category_account.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/data/ledger_read_repository.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';
import 'package:so_account/features/statistics/data/statistics_repository.dart';
import 'package:so_account/features/statistics/domain/report_range.dart';

void main() {
  late AppDatabase db;
  late LedgerRepository repo;
  late String a, b;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = LedgerRepository(db);
    a = await repo.saveAccount(
      name: '合成现金',
      kind: '资金账户',
      channel: '现金',
      currency: 'CNY',
      openingBalance: 100000,
    );
    b = await repo.saveAccount(
      name: '合成零钱',
      kind: '资金账户',
      channel: '微信',
      currency: 'CNY',
      openingBalance: 20000,
    );
  });
  tearDown(() => db.close());
  Future<String> save(
    String account,
    String category, {
    String? id,
    EntryKind kind = EntryKind.expense,
    int amount = 100,
  }) => repo.saveEntry(
    id: id,
    kind: kind,
    amount: amount,
    accountId: account,
    categoryId: category,
    date: '2026-10-10',
  );
  Future<String?> remembered(
    String category, {
    String kind = 'expense',
  }) async =>
      (await (db.select(db.preferences)..where(
                (p) => p.key.equals(recentCategoryAccountKey(kind, category)),
              ))
              .getSingleOrNull())
          ?.value;
  test('successful new entries independently persist category accounts; edits and failed saves do not replace them', () async {
    final first = await save(a, 'expense-0');
    await save(b, 'expense-1');
    await save(b, 'income-0', kind: EntryKind.income);
    expect(await remembered('expense-0'), a);
    expect(await remembered('expense-1'), b);
    expect(await remembered('income-0', kind: 'income'), b);
    await save(b, 'expense-0', id: first);
    expect(await remembered('expense-0'), a);
    await expectLater(save(b, 'expense-0', amount: 0), throwsFormatException);
    expect(await remembered('expense-0'), a);
    await save(b, 'expense-0');
    expect(await remembered('expense-0'), b);
    // A fresh repository reads persisted preferences, without an in-memory cache.
    expect((await LedgerRepository(db).balances())[b], 19800);
  });
  test('loans and settlements are separate from income, expense, budgets, daily and chart totals', () async {
    await save(a, 'expense-0', amount: 1200);
    await save(a, 'income-0', kind: EntryKind.income, amount: 3000);
    final borrow = await repo.saveEntry(
      kind: EntryKind.borrow,
      amount: 5000,
      accountId: a,
      date: '2026-10-10',
    );
    final lend = await repo.saveEntry(
      kind: EntryKind.lend,
      amount: 2000,
      accountId: a,
      date: '2026-10-10',
    );
    await repo.saveEntry(
      kind: EntryKind.repay,
      amount: 700,
      accountId: a,
      debtId: borrow,
      date: '2026-10-11',
    );
    await repo.saveEntry(
      kind: EntryKind.collect,
      amount: 600,
      accountId: a,
      debtId: lend,
      date: '2026-10-11',
    );
    final report = await StatisticsRepository(db)
        .load(ReportRange.at(ReportPeriod.month, DateTime(2026, 10)), 'CNY');
    expect(report.income, 3000);
    expect(report.expense, 1200);
    expect(report.surplus, 1800);
    expect(report.borrow, 5000);
    expect(report.lend, 2000);
    expect(report.repay, 700);
    expect(report.collect, 600);
    expect(report.points.fold<int>(0, (v, p) => v + p.income), 3000);
    expect(report.points.fold<int>(0, (v, p) => v + p.expense), 1200);
    expect(report.points.last.netAssets, 121800);
    final home = await LedgerReadRepository(db).home((
      month: '2026-10',
      currency: 'CNY',
      day: null,
      kind: null,
      category: null,
      search: '',
      limit: 100,
    ));
    expect(home.totals['income'], 3000);
    expect(home.totals['expense'], 1200);
    expect(home.totals['borrow'], 5000);
    expect(home.daily['2026-10-10'], {'income': 3000, 'expense': 1200});
    final usd = await StatisticsRepository(db)
        .load(ReportRange.at(ReportPeriod.month, DateTime(2026, 10)), 'USD');
    expect(usd.borrow + usd.lend + usd.income + usd.expense, 0);
  });
}
