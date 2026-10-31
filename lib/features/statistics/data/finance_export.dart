import 'package:drift/drift.dart';

import '../../../core/category_preferences.dart';
import '../../../core/money/money.dart';
import '../../../core/time/business_date.dart';
import '../../../data/app_snapshot.dart';
import '../../../data/database/app_database.dart';
import '../../ledger/data/ledger_repository.dart';
import '../../ledger/domain/entry_kind.dart';

const financeExportBasis =
    '收支仅统计收入和支出，不含转账、借贷本金、报销垫付/回款及投资投入/收回。'
    '资产和负债为各月末账面余额（含归档账户），由现有期初余额、历史流水和余额调整回算；'
    '账户没有期初日期，现有期初余额适用于全部历史月份。理财按买入成本，不代表实时净值。';

class ExportColumn {
  const ExportColumn(this.id, this.name);
  final String id, name;
}

class FinanceMonth {
  const FinanceMonth(
    this.date,
    this.income,
    this.expense,
    this.assets,
    this.debt,
  );
  final DateTime date;
  final Map<String, int> income, expense, assets, debt;
  int total(Map<String, int> values) => values.values.fold(0, (a, b) => a + b);
  int get totalIncome => total(income);
  int get totalExpense => total(expense);
  int get totalAssets => total(assets);
  int get totalDebt => total(debt);
  int get netIncome => totalIncome - totalExpense;
  int get netAssets => totalAssets - totalDebt;
}

class FinanceExportData {
  const FinanceExportData({
    required this.currency,
    required this.months,
    required this.incomeColumns,
    required this.expenseColumns,
    required this.assetColumns,
    required this.debtColumns,
  });
  final String currency;
  final List<FinanceMonth> months;
  final List<ExportColumn> incomeColumns,
      expenseColumns,
      assetColumns,
      debtColumns;
}

class FinanceExportRepository {
  FinanceExportRepository(this.db);
  final AppDatabase db;

  Future<FinanceExportData> loadAll(String currency, DateTime through) =>
      db.transaction(() async {
        var end = DateTime(through.year, through.month + 1);
        final latest = await db
            .customSelect(
              '''
          SELECT MAX(date) AS date FROM (
            SELECT e.date FROM entries e JOIN accounts a ON a.id=e.account_id WHERE a.currency=?
            UNION ALL SELECT b.date FROM balance_adjustments b JOIN accounts a ON a.id=b.account_id WHERE a.currency=?
          )''',
              variables: [Variable(currency), Variable(currency)],
            )
            .getSingle();
        final last = latest.readNullable<String>('date');
        if (last != null) {
          final d = parseDate(last);
          final next = DateTime(d.year, d.month + 1);
          if (next.isAfter(end)) end = next;
        }
        return load(currency, null, end);
      });

  Stream<FinanceExportData> watch(
    String currency,
    DateTime start,
    DateTime end,
  ) => db
      .customSelect(
        'SELECT 1',
        readsFrom: {
          db.accounts,
          db.categories,
          db.entries,
          db.balanceAdjustments,
          db.preferences,
        },
      )
      .watch()
      .asyncMap((_) => load(currency, start, end));

  /// The end is exclusive. A null start exports all recorded months through end.
  Future<FinanceExportData> load(
    String currency,
    DateTime? start,
    DateTime end,
  ) => db.transaction(() async {
    fractionDigits(currency);
    final accounts =
        await (db.select(db.accounts)
              ..where((a) => a.currency.equals(currency))
              ..orderBy([(a) => OrderingTerm.asc(a.id)]))
            .get();
    final preferences = await db.select(db.preferences).get();
    final snapshot = AppSnapshot(
      [],
      await db.select(db.categories).get(),
      [],
      [],
      [],
      [],
      preferences,
    );
    final order = decodeCategoryOrder(
      snapshot.preference('account_order', '[]'),
    );
    final ranks = {for (var i = 0; i < order.length; i++) order[i]: i};
    accounts.sort((a, b) {
      final rank = (ranks[a.id] ?? order.length).compareTo(
        ranks[b.id] ?? order.length,
      );
      return rank != 0 ? rank : a.id.compareTo(b.id);
    });
    // Aggregate in SQLite, with no transaction display limit or list of bound IDs.
    final changes = await db
        .customSelect(
          '''
      SELECT id,month,SUM(delta) AS delta FROM (
        SELECT a.id,substr(e.date,1,7) AS month,
          ${LedgerRepository.balanceEntryDeltaSql} AS delta
        FROM accounts a JOIN entries e
          ON e.account_id=a.id OR e.target_account_id=a.id OR e.debt_account_id=a.id
        WHERE a.currency=? AND e.date<?
        UNION ALL
        SELECT a.id,substr(b.date,1,7),b.delta
        FROM accounts a JOIN balance_adjustments b ON b.account_id=a.id
        WHERE a.currency=? AND b.date<?
      ) GROUP BY id,month ORDER BY month,id
    ''',
          variables: [
            Variable(currency),
            Variable(dateKey(end)),
            Variable(currency),
            Variable(dateKey(end)),
          ],
        )
        .get();
    final flows = await db
        .customSelect(
          '''
      SELECT substr(e.date,1,7) AS month,e.kind,e.category_id,SUM(e.amount) AS amount
      FROM entries e JOIN accounts a ON a.id=e.account_id
      WHERE a.currency=? AND e.date<? AND e.kind IN ('income','expense')
      GROUP BY month,e.kind,e.category_id ORDER BY month
    ''',
          variables: [Variable(currency), Variable(dateKey(end))],
        )
        .get();
    final first =
        start ??
        (changes.isEmpty
            ? DateTime(end.year, end.month - 1)
            : parseDate('${changes.first.read<String>('month')}-01'));
    final count = (end.year - first.year) * 12 + end.month - first.month;
    if (first.day != 1 || end.day != 1 || count < 1 || count > 2412) {
      throw const FormatException('请选择有效月份范围，最多 201 年');
    }
    final balances = {for (final a in accounts) a.id: a.openingBalance};
    var changeIndex = 0;
    final months = <FinanceMonth>[];
    final flowByMonth = <String, Map<String, Map<String, int>>>{};
    for (final row in flows) {
      final byKind = flowByMonth.putIfAbsent(
        row.read<String>('month'),
        () => {},
      );
      (byKind[row.read<String>('kind')] ??=
          {})[row.readNullable<String>('category_id') ?? 'uncategorized'] = row
          .read<int>('amount');
    }
    for (var i = 0; i < count; i++) {
      final date = DateTime(first.year, first.month + i);
      final key = monthKey(date);
      while (changeIndex < changes.length &&
          changes[changeIndex].read<String>('month').compareTo(key) <= 0) {
        final row = changes[changeIndex++];
        balances.update(
          row.read<String>('id'),
          (b) => b + row.read<int>('delta'),
        );
      }
      final assets = <String, int>{}, debt = <String, int>{};
      for (final a in accounts) {
        final balance = assetBalance(a.channel, balances[a.id]!);
        assets[a.id] = balance > 0 ? balance : 0;
        debt[a.id] = balance < 0 ? -balance : 0;
      }
      months.add(
        FinanceMonth(
          date,
          flowByMonth[key]?['income'] ?? {},
          flowByMonth[key]?['expense'] ?? {},
          assets,
          debt,
        ),
      );
    }
    List<ExportColumn> categories(String kind) => [
      for (final c in snapshot.categories.where((c) => c.kind == kind))
        ExportColumn(c.id, c.name),
      if (months.any(
        (m) => (kind == 'income' ? m.income : m.expense).containsKey(
          'uncategorized',
        ),
      ))
        const ExportColumn('uncategorized', '未分类'),
    ];
    // Preserve distinct IDs when the same person has both payable and receivable.
    final names = <String, int>{};
    final columns = <String, ExportColumn>{};
    for (final a in accounts) {
      var name = a.name;
      if (a.kind == '债务') name += '（${a.channel}）';
      if (a.kind == '投资理财') name += '（买入成本）';
      if (a.isArchived) name += '（已归档）';
      final n = names.update(name, (n) => n + 1, ifAbsent: () => 1);
      columns[a.id] = ExportColumn(a.id, n == 1 ? name : '$name [$n]');
    }
    return FinanceExportData(
      currency: currency,
      months: months,
      incomeColumns: categories('income'),
      expenseColumns: categories('expense'),
      assetColumns: [
        for (final a in accounts)
          if ((a.kind != '信贷账户' && a.channel != '应付款') ||
              months.any((m) => m.assets[a.id]! > 0))
            columns[a.id]!,
      ],
      debtColumns: [
        for (final a in accounts)
          if (a.kind == '信贷账户' ||
              a.channel == '应付款' ||
              months.any((m) => m.debt[a.id]! > 0))
            columns[a.id]!,
      ],
    );
  });
}

String exportGrowth(int current, int previous) => previous == 0
    ? (current == 0 ? '0.00%' : 'NULL')
    : '${((current - previous) / previous * 100).toStringAsFixed(2)}%';

String _markdownCell(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('\\', '&#92;')
    .replaceAll('|', '&#124;')
    .replaceAll('\r\n', '<br>')
    .replaceAll('\n', '<br>')
    .replaceAll('\r', '<br>')
    .replaceAll('*', '&#42;')
    .replaceAll('_', '&#95;')
    .replaceAll('`', '&#96;');

String monthlyMarkdown(
  FinanceExportData data, {
  String notes = '',
  bool hideAssets = false,
}) {
  if (data.months.length != 2) {
    throw const FormatException('月度总结需要本月与上月数据');
  }
  final previous = data.months.first, current = data.months.last;
  final text = StringBuffer('# ${monthKey(current.date)} 月度总结\n\n');
  text.writeln(
    '币种：${data.currency}；本月：${monthKey(current.date)}；上月：${monthKey(previous.date)}。\n',
  );
  text.writeln('# 总体概况\n');
  text.writeln('| 指标 | 本月 | 上月 | 增长率 (%) |');
  text.writeln('| --- | --- | --- | --- |');
  for (final row in [
    ('总收入', current.totalIncome, previous.totalIncome, false),
    ('总支出', current.totalExpense, previous.totalExpense, false),
    ('净收入', current.netIncome, previous.netIncome, false),
    ('总资产', current.totalAssets, previous.totalAssets, true),
    ('总负债', current.totalDebt, previous.totalDebt, true),
    ('净资产', current.netAssets, previous.netAssets, true),
  ]) {
    final masked = hideAssets && row.$4;
    text.writeln(
      '| ${row.$1} | ${masked ? '••••' : decimalMoney(row.$2, data.currency)} | '
      '${masked ? '••••' : decimalMoney(row.$3, data.currency)} | '
      '${masked ? '••••' : exportGrowth(row.$2, row.$3)} |',
    );
  }
  text.writeln('\n# 明细\n');
  void section(
    String title,
    String totalLabel,
    List<ExportColumn> columns,
    Map<String, int> now,
    Map<String, int> before,
    int total,
    int oldTotal, {
    bool asset = false,
  }) {
    final masked = hideAssets && asset;
    text.writeln('## $title\n');
    text.writeln('| 类别 | 本月 | 占$totalLabel比例(%) | 上月 | 增长率(%) |');
    text.writeln('| --- | --- | --- | --- | --- |');
    for (final c in columns) {
      final value = now[c.id] ?? 0, old = before[c.id] ?? 0;
      final share = total == 0
          ? '0.00%'
          : '${(value / total * 100).toStringAsFixed(2)}%';
      text.writeln(
        '| ${_markdownCell(c.name)} | ${masked ? '••••' : decimalMoney(value, data.currency)} | '
        '${masked ? '••••' : share} | ${masked ? '••••' : decimalMoney(old, data.currency)} | '
        '${masked ? '••••' : exportGrowth(value, old)} |',
      );
    }
    text.writeln(
      '| **$totalLabel** | ${masked ? '••••' : decimalMoney(total, data.currency)} | '
      '${masked ? '••••' : (total == 0 ? '0.00%' : '100%')} | '
      '${masked ? '••••' : decimalMoney(oldTotal, data.currency)} | '
      '${masked ? '••••' : exportGrowth(total, oldTotal)} |\n',
    );
  }

  section(
    '支出明细',
    '总支出',
    data.expenseColumns,
    current.expense,
    previous.expense,
    current.totalExpense,
    previous.totalExpense,
  );
  section(
    '收入明细',
    '总收入',
    data.incomeColumns,
    current.income,
    previous.income,
    current.totalIncome,
    previous.totalIncome,
  );
  section(
    '资产明细',
    '总资产',
    data.assetColumns,
    current.assets,
    previous.assets,
    current.totalAssets,
    previous.totalAssets,
    asset: true,
  );
  section(
    '负债明细',
    '总负债',
    data.debtColumns,
    current.debt,
    previous.debt,
    current.totalDebt,
    previous.totalDebt,
    asset: true,
  );
  text.writeln('## 统计口径\n\n$financeExportBasis\n');
  text.writeln('增长率 =（本月 − 上月）÷ 上月；上月为 0 且本月非 0 时为 NULL，两月均为 0 时为 0.00%。\n');
  if (hideAssets) text.writeln('资产金额、占比及增长率已隐藏。\n');
  text.writeln('## 说明\n');
  if (notes.trim().isNotEmpty) text.writeln(notes.trim());
  return text.toString();
}
