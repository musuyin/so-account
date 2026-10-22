import 'package:drift/drift.dart';

import '../../../core/time/business_date.dart';
import '../../../data/database/app_database.dart';
import '../domain/report_range.dart';

class ReportPoint {
  const ReportPoint(this.label, this.income, this.expense, this.netAssets);
  final String label;
  final int income, expense, netAssets;
}

class CategoryComparison {
  const CategoryComparison(
    this.id,
    this.name,
    this.kind,
    this.amount,
    this.previous,
  );
  final String id, name, kind;
  final int amount, previous;
  int get delta => amount - previous;
  double? get growth => previous == 0 ? null : delta / previous;
  bool get improved => kind == 'income' ? delta > 0 : delta < 0;
}

class FinanceReport {
  const FinanceReport({
    required this.range,
    this.income = 0,
    this.expense = 0,
    this.previousIncome = 0,
    this.previousExpense = 0,
    this.points = const [],
    this.categories = const [],
  });
  final ReportRange range;
  final int income, expense, previousIncome, previousExpense;
  final List<ReportPoint> points;
  final List<CategoryComparison> categories;
  int get surplus => income - expense;
  double get dailyIncome => income / range.days;
  double get dailyExpense => expense / range.days;
}

class StatisticsRepository {
  StatisticsRepository(this.db);
  final AppDatabase db;
  Stream<FinanceReport> watchReport(ReportRange range, String currency) => db
      .customSelect(
        'SELECT 1',
        readsFrom: {
          db.entries,
          db.accounts,
          db.categories,
          db.balanceAdjustments,
        },
      )
      .watch()
      .asyncMap((_) => load(range, currency));
  Future<FinanceReport> load(ReportRange range, String currency) =>
      db.transaction(() async {
        if (range.days <= 0 || range.days > 3660) {
          throw const FormatException('统计范围需为 1–3660 天');
        }
        final previous = range.previous;
        final rows = await db
            .customSelect(
              '''
      SELECT e.kind, CASE WHEN e.date >= ? THEN 'current' ELSE 'previous' END AS period, SUM(e.amount) AS amount
      FROM entries e JOIN accounts a ON a.id=e.account_id
      WHERE a.currency=? AND e.date>=? AND e.date<? AND e.kind IN ('income','expense')
      GROUP BY e.kind,period
    ''',
              variables: [
                Variable(dateKey(range.start)),
                Variable(currency),
                Variable(dateKey(previous.start)),
                Variable(dateKey(range.end)),
              ],
            )
            .get();
        int total(String kind, String period) =>
            rows
                .where(
                  (r) =>
                      r.read<String>('kind') == kind &&
                      r.read<String>('period') == period,
                )
                .firstOrNull
                ?.read<int>('amount') ??
            0;
        final categoryRows = await db
            .customSelect(
              '''
      SELECT c.id,c.name,e.kind,
        SUM(CASE WHEN e.date>=? THEN e.amount ELSE 0 END) AS amount,
        SUM(CASE WHEN e.date<? THEN e.amount ELSE 0 END) AS previous
      FROM entries e JOIN accounts a ON a.id=e.account_id JOIN categories c ON c.id=e.category_id
      WHERE a.currency=? AND e.date>=? AND e.date<? AND e.kind IN ('income','expense')
      GROUP BY c.id,c.name,e.kind ORDER BY amount DESC,c.name
    ''',
              variables: [
                Variable(dateKey(range.start)),
                Variable(dateKey(range.start)),
                Variable(currency),
                Variable(dateKey(previous.start)),
                Variable(dateKey(range.end)),
              ],
            )
            .get();
        final changes = await db
            .customSelect(
              '''
      SELECT date,SUM(income) AS income,SUM(expense) AS expense,SUM(correction) AS correction FROM (
        SELECT e.date,CASE WHEN e.kind='income' THEN e.amount ELSE 0 END AS income,
          CASE WHEN e.kind='expense' THEN e.amount ELSE 0 END AS expense,0 AS correction
        FROM entries e JOIN accounts a ON a.id=e.account_id
        WHERE a.currency=? AND e.date<? AND e.kind IN ('income','expense')
        UNION ALL
        SELECT b.date,0 AS income,0 AS expense,
          CASE WHEN a.kind='债务' AND a.channel='应付款' THEN -b.delta ELSE b.delta END AS correction
        FROM balance_adjustments b JOIN accounts a ON a.id=b.account_id WHERE a.currency=? AND b.date<?
      ) GROUP BY date ORDER BY date
    ''',
              variables: [
                Variable(currency),
                Variable(dateKey(range.end)),
                Variable(currency),
                Variable(dateKey(range.end)),
              ],
            )
            .get();
        final opening = await db
            .customSelect(
              "SELECT COALESCE(SUM(CASE WHEN kind='债务' AND channel='应付款' THEN -opening_balance ELSE opening_balance END),0) AS amount FROM accounts WHERE currency=?",
              variables: [Variable(currency)],
            )
            .getSingle();
        var assets = opening.read<int>('amount'), index = 0;
        while (index < changes.length &&
            changes[index]
                    .read<String>('date')
                    .compareTo(dateKey(range.start)) <
                0) {
          assets +=
              changes[index].read<int>('income') -
              changes[index].read<int>('expense') +
              changes[index].read<int>('correction');
          index++;
        }
        final points = <ReportPoint>[];
        for (final key in range.buckets) {
          var income = 0, expense = 0, correction = 0;
          while (index < changes.length &&
              changes[index].read<String>('date').startsWith(key)) {
            income += changes[index].read<int>('income');
            expense += changes[index].read<int>('expense');
            correction += changes[index].read<int>('correction');
            index++;
          }
          assets += income - expense + correction;
          points.add(ReportPoint(key, income, expense, assets));
        }
        return FinanceReport(
          range: range,
          income: total('income', 'current'),
          expense: total('expense', 'current'),
          previousIncome: total('income', 'previous'),
          previousExpense: total('expense', 'previous'),
          points: points,
          categories: categoryRows
              .map(
                (r) => CategoryComparison(
                  r.read<String>('id'),
                  r.read<String>('name'),
                  r.read<String>('kind'),
                  r.read<int>('amount'),
                  r.read<int>('previous'),
                ),
              )
              .toList(),
        );
      });
}
