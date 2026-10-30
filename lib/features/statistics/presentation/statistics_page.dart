import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/providers.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/widgets.dart';
import 'report_records_page.dart';
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
  bool line = false, categoryBars = false;
  bool get assetsHidden => ref.watch(assetAmountsHiddenProvider);
  FlowMetric metric = FlowMetric.compare;
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
          DropdownButton<String>(
            key: const ValueKey('statistics-currency'),
            value: currency,
            underline: const SizedBox.shrink(),
            items: [
              for (final value in currencies)
                DropdownMenuItem(value: value, child: Text(value)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => currency = value);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Wrap(
            spacing: 6,
            children: [
              for (final entry in {
                ReportPeriod.week: '近7天',
                ReportPeriod.month: '月',
                ReportPeriod.year: '年',
                ReportPeriod.custom: '自定义',
              }.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: period == entry.key,
                  onSelected: (_) => setState(() => period = entry.key),
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
              final categories = data.categories
                  .where((c) => c.kind == categoryKind)
                  .toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    borderOnForeground: false,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          MoneySummary(
                            values: [
                              (
                                label: '$prefix支出',
                                amount: decimalMoney(data.expense, currency),
                                color: expenseColor(context),
                              ),
                              (
                                label: '$prefix收入',
                                amount: decimalMoney(data.income, currency),
                                color: incomeColor(context),
                              ),
                              (
                                label: '$prefix结余',
                                amount: decimalMoney(data.surplus, currency),
                                color: null,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '日均支出 ${(data.dailyExpense / factor).toStringAsFixed(fractionDigits(currency))}',
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  '日均收入 ${(data.dailyIncome / factor).toStringAsFixed(fractionDigits(currency))}',
                                ),
                              ),
                            ],
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '完整周期 ${r.days} 天，日均按该天数计算',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (data.borrow != 0 ||
                      data.lend != 0 ||
                      data.repay != 0 ||
                      data.collect != 0)
                    Card(
                      key: const ValueKey('statistics-loans'),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('借贷本金'),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 16,
                              runSpacing: 8,
                              children: [
                                for (final row in [
                                  ('借入', data.borrow),
                                  ('借出', data.lend),
                                  ('偿还借入', data.repay),
                                  ('收回借出', data.collect),
                                ])
                                  ParameterText(
                                    '${row.$1} ${decimalMoney(row.$2, currency)}',
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  _section(
                    '收支趋势',
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: 6,
                          children: [
                            for (final value in [false, true])
                              ChoiceChip(
                                label: Text(value ? '折线图' : '柱状图'),
                                selected: line == value,
                                onSelected: (_) => setState(() => line = value),
                              ),
                          ],
                        ),
                        Wrap(
                          spacing: 6,
                          children: [
                            for (final entry in {
                              FlowMetric.compare: '收支对比',
                              FlowMetric.expense: '支出',
                              FlowMetric.income: '收入',
                              FlowMetric.surplus: '结余',
                            }.entries)
                              ChoiceChip(
                                label: Text(entry.value),
                                selected: metric == entry.key,
                                onSelected: (_) =>
                                    setState(() => metric = entry.key),
                              ),
                          ],
                        ),
                        FlowBars(
                          points: data.points,
                          currency: currency,
                          line: line,
                          metric: metric,
                          onRecords: (p) {
                            final interval = r.intervalFor(p.label);
                            records(
                              interval.$1,
                              interval.$2,
                              kind: metric == FlowMetric.expense
                                  ? 'expense'
                                  : metric == FlowMetric.income
                                  ? 'income'
                                  : null,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  ...[
                    _section(
                      '上期收支对比',
                      FlowBars(
                        groupByMetric: true,
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
                      '',
                      Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                Text(
                                  categoryBars
                                      ? '分类排名'
                                      : categoryKind == 'expense'
                                      ? '支出占比'
                                      : '收入占比',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                SegmentedButton<String>(
                                  showSelectedIcon: false,
                                  segments: const [
                                    ButtonSegment(
                                      value: 'expense',
                                      label: Text('支出'),
                                    ),
                                    ButtonSegment(
                                      value: 'income',
                                      label: Text('收入'),
                                    ),
                                  ],
                                  selected: {categoryKind},
                                  onSelectionChanged: (selection) => setState(
                                    () => categoryKind = selection.first,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Wrap(
                            spacing: 6,
                            children: [
                              for (final value in [false, true])
                                ChoiceChip(
                                  label: Text(value ? '条形排名' : '环形图'),
                                  selected: categoryBars == value,
                                  onSelected: (_) =>
                                      setState(() => categoryBars = value),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          CategoryPie(
                            categories: categories,
                            currency: currency,
                            bars: categoryBars,
                            onRecords: (c) => records(
                              r.start,
                              r.end,
                              category: c.id,
                              kind: categoryKind,
                            ),
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
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextButton.icon(
                            onPressed: () => ref
                                .read(assetAmountsHiddenProvider.notifier)
                                .toggle(),
                            icon: Icon(
                              assetsHidden
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            label: Text(assetsHidden ? '显示资产金额' : '隐藏资产金额'),
                          ),
                          if (assetsHidden)
                            const Text('资产金额已隐藏')
                          else
                            AssetLine(points: data.points, currency: currency),
                          const SizedBox(height: 8),
                          const Text(
                            '按初始余额、历史收支和余额调整推算；借贷和转账不改变净资产。',
                            style: TextStyle(fontSize: 12),
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

  void records(DateTime start, DateTime end, {String? category, String? kind}) {
    openForm(
      context,
      ReportRecordsPage(
        start: dateKey(start),
        end: dateKey(end),
        currency: currency,
        category: category,
        kind: kind,
      ),
    );
  }

  Widget _section(String title, Widget child) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title.isNotEmpty) ...[
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
        ],
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
        ? (c.amount == 0 ? '上期为0' : '新增（上期为0）')
        : '${c.delta > 0 ? '+' : ''}${(c.growth! * 100).toStringAsFixed(1)}%';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(c.name)),
              Text(decimalMoney(c.amount, currency)),
            ],
          ),
          const SizedBox(height: 4),
          ParameterRow([
            '上期 ${decimalMoney(c.previous, currency)}',
            '差额 ${c.delta > 0 ? '+' : ''}${decimalMoney(c.delta, currency)}',
            growth,
          ], style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}
