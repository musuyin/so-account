import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/providers.dart';
import '../../../core/money/money.dart';
import '../../../core/time/business_date.dart';
import '../domain/report_range.dart';
import '../data/statistics_repository.dart';
import 'report_charts.dart';

final reportProvider =
    StreamProvider.family<FinanceReport, (String, String, String, String)>(
      (ref, key) =>
          StatisticsRepository(ref.watch(databaseProvider)).watchReport(
            ReportRange(
              parseDate(key.$2),
              parseDate(key.$3),
              ReportPeriod.values.byName(key.$1),
            ),
            key.$4,
          ),
    );

class StatisticsPage extends ConsumerStatefulWidget {
  const StatisticsPage({super.key});
  @override
  ConsumerState<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends ConsumerState<StatisticsPage> {
  ReportPeriod period = ReportPeriod.month;
  DateTime anchor = DateTime.now();
  DateTime? customStart, customEnd;
  String currency = 'CNY', categoryKind = 'expense';
  ReportRange get range => ReportRange.at(
    period,
    anchor,
    customStart: customStart,
    customEnd: customEnd,
  );
  void move(int delta) => setState(() {
    anchor = switch (period) {
      ReportPeriod.week => DateTime(
        anchor.year,
        anchor.month,
        anchor.day + 7 * delta,
      ),
      ReportPeriod.month => DateTime(anchor.year, anchor.month + delta),
      ReportPeriod.year => DateTime(anchor.year + delta),
      ReportPeriod.custom => anchor,
    };
  });
  Future<void> selectRange() async {
    if (period == ReportPeriod.custom) {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(1900),
        lastDate: DateTime(2100),
        initialDateRange: DateTimeRange(
          start: range.start,
          end: DateTime(range.end.year, range.end.month, range.end.day - 1),
        ),
      );
      if (picked != null) {
        setState(() {
          customStart = picked.start;
          customEnd = picked.end;
        });
      }
    } else {
      final picked = await showDatePicker(
        context: context,
        firstDate: DateTime(1900),
        lastDate: DateTime(2100),
        initialDate: anchor,
      );
      if (picked != null) setState(() => anchor = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = range;
    final key = (period.name, dateKey(r.start), dateKey(r.end), currency);
    final report = ref.watch(reportProvider(key));
    return Scaffold(
      appBar: AppBar(
        title: const Text('统计'),
        actions: [
          DropdownButton(
            value: currency,
            items: currencies
                .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                .toList(),
            onChanged: (v) => setState(() => currency = v!),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              for (final entry in {
                ReportPeriod.week: '周',
                ReportPeriod.month: '月',
                ReportPeriod.year: '年',
                ReportPeriod.custom: '自定义',
              }.entries)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: ChoiceChip(
                      label: Text(entry.value),
                      selected: period == entry.key,
                      onSelected: (_) => setState(() => period = entry.key),
                    ),
                  ),
                ),
            ],
          ),
          Row(
            children: [
              if (period != ReportPeriod.custom)
                IconButton(
                  tooltip: '上一期',
                  onPressed: () => move(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
              Expanded(
                child: TextButton(
                  onPressed: selectRange,
                  child: Text(
                    '${dateKey(r.start)} — ${dateKey(DateTime(r.end.year, r.end.month, r.end.day - 1))}',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              if (period != ReportPeriod.custom)
                IconButton(
                  tooltip: '下一期',
                  onPressed: () => move(1),
                  icon: const Icon(Icons.chevron_right),
                ),
            ],
          ),
          report.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => Column(
              children: [
                const Text('统计读取失败，范围最多十年'),
                TextButton(
                  onPressed: () => ref.invalidate(reportProvider(key)),
                  child: const Text('重试'),
                ),
              ],
            ),
            data: (data) {
              final prefix = period == ReportPeriod.year
                  ? '年'
                  : period == ReportPeriod.month
                  ? '月'
                  : period == ReportPeriod.week
                  ? '7天'
                  : '';
              final factor = currency == 'JPY' ? 1 : 100;
              Widget metric(String label, int value) => Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        decimalMoney(value, currency),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
              );
              final categories = data.categories
                  .where((c) => c.kind == categoryKind)
                  .toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    borderOnForeground: false,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              metric('$prefix支出', data.expense),
                              metric('$prefix收入', data.income),
                              metric('$prefix结余', data.surplus),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '日均支出 ${(data.dailyExpense / factor).toStringAsFixed(2)}',
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  '日均收入 ${(data.dailyIncome / factor).toStringAsFixed(2)}',
                                ),
                              ),
                            ],
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${r.days} 天',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _section(
                    '收入 / 支出柱状图',
                    FlowBars(points: data.points, currency: currency),
                  ),
                  if (period != ReportPeriod.week) ...[
                    _section(
                      '收支对比',
                      FlowBars(
                        points: [
                          ReportPoint(
                            '上期',
                            data.previousIncome,
                            data.previousExpense,
                            0,
                          ),
                          ReportPoint('本期', data.income, data.expense, 0),
                        ],
                        currency: currency,
                      ),
                    ),
                    _section(
                      '分类占比',
                      Column(
                        children: [
                          Wrap(
                            spacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text('支出'),
                                selected: categoryKind == 'expense',
                                onSelected: (_) =>
                                    setState(() => categoryKind = 'expense'),
                              ),
                              ChoiceChip(
                                label: const Text('收入'),
                                selected: categoryKind == 'income',
                                onSelected: (_) =>
                                    setState(() => categoryKind = 'income'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          CategoryPie(
                            categories: categories,
                            currency: currency,
                          ),
                        ],
                      ),
                    ),
                    _section(
                      period == ReportPeriod.year
                          ? '与去年对比'
                          : period == ReportPeriod.month
                          ? '与上个月对比'
                          : '与上一等长区间对比',
                      Column(
                        children: [
                          for (final c in [
                            CategoryComparison(
                              'total-expense',
                              '总支出',
                              'expense',
                              data.expense,
                              data.previousExpense,
                            ),
                            CategoryComparison(
                              'total-income',
                              '总收入',
                              'income',
                              data.income,
                              data.previousIncome,
                            ),
                            ...data.categories,
                          ])
                            _comparison(context, c),
                        ],
                      ),
                    ),
                  ],
                  if (period == ReportPeriod.year ||
                      period == ReportPeriod.custom)
                    _section(
                      '净资产走势',
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AssetLine(points: data.points, currency: currency),
                          const SizedBox(height: 8),
                          const Text(
                            '根据账户初始余额和历史收支推算；借贷和转账不改变净资产。',
                            style: TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _section(String title, Widget child) => Padding(
    padding: const EdgeInsets.only(top: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Card(
          borderOnForeground: false,
          child: Padding(padding: const EdgeInsets.all(12), child: child),
        ),
      ],
    ),
  );
  Widget _comparison(BuildContext context, CategoryComparison c) {
    final color = c.delta == 0
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : c.improved
        ? incomeColor(context)
        : expenseColor(context);
    final growth = c.growth == null
        ? '-'
        : '${c.delta > 0 ? '+' : ''}${(c.growth! * 100).toStringAsFixed(1)}%';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${c.name} · ${c.kind == 'income' ? '收入' : '支出'}'),
              ),
              Text(decimalMoney(c.amount, currency)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '上期 ${decimalMoney(c.previous, currency)} · 差额 ${c.delta > 0 ? '+' : ''}${decimalMoney(c.delta, currency)} · $growth',
            style: TextStyle(color: color, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
