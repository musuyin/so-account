import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/providers.dart';
import '../../../app/widgets.dart';
import '../../../core/money/money.dart';
import '../../../core/time/business_date.dart';
import '../data/statistics_repository.dart';

final breakdownProvider =
    StreamProvider.family<List<Breakdown>, (String, String)>(
      (ref, key) =>
          StatisticsRepository(ref.watch(databaseProvider))
              .watchBreakdown(parseDate('${key.$1}-01'), key.$2),
    );
final trendProvider = StreamProvider.family<List<Trend>, (String, String)>(
  (ref, key) =>
      StatisticsRepository(ref.watch(databaseProvider))
          .watchTrend(parseDate('${key.$1}-01'), key.$2),
);

class StatisticsPage extends ConsumerStatefulWidget {
  const StatisticsPage({super.key});
  @override
  ConsumerState<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends ConsumerState<StatisticsPage> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  String currency = 'CNY';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('收支有数')),
    body: DataView(
      builder: (data) {
        final breakdown = ref.watch(
          breakdownProvider((monthKey(month), currency)),
        );
        final trend = ref.watch(trendProvider((monthKey(month), currency)));
        final debts = data.entries
            .where(
              (e) =>
                  ['borrow', 'lend'].contains(e.kind) &&
                  data.account(e.accountId).currency == currency,
            )
            .toList();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: '上个月',
                  onPressed: () => setState(
                    () => month = DateTime(month.year, month.month - 1),
                  ),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    '${month.year} 年 ${month.month} 月',
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  tooltip: '下个月',
                  onPressed: () => setState(
                    () => month = DateTime(month.year, month.month + 1),
                  ),
                  icon: const Icon(Icons.chevron_right),
                ),
                DropdownButton(
                  value: currency,
                  items: currencies
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) => setState(() => currency = v!),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('分类收支', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            breakdown.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const Text('读取统计失败'),
              data: (rows) {
                final expense = rows
                    .where((r) => r.kind == 'expense')
                    .fold<int>(0, (s, r) => s + r.amount);
                return Column(
                  children: [
                    if (rows.isEmpty)
                      const EmptyState('本月暂无收支', '转账和借贷本金不计入收入与支出。'),
                    for (final r in rows)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${r.name} · ${r.kind == 'expense' ? '支出' : '收入'}',
                                    ),
                                  ),
                                  Text(money(r.amount, currency)),
                                ],
                              ),
                              if (r.kind == 'expense') ...[
                                const SizedBox(height: 10),
                                LinearProgressIndicator(
                                  value: expense == 0 ? 0 : r.amount / expense,
                                  minHeight: 6,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            Text('近六个月', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            trend.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const Text('读取趋势失败'),
              data: (rows) => Column(
                children: [
                  for (var i = 5; i >= 0; i--)
                    Builder(
                      builder: (context) {
                        final key = monthKey(
                          DateTime(month.year, month.month - i),
                        );
                        final income =
                            rows
                                .where(
                                  (r) => r.month == key && r.kind == 'income',
                                )
                                .firstOrNull
                                ?.amount ??
                            0;
                        final expense =
                            rows
                                .where(
                                  (r) => r.month == key && r.kind == 'expense',
                                )
                                .firstOrNull
                                ?.amount ??
                            0;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(key),
                          subtitle: Text(
                            '收入 ${decimalMoney(income, currency)} · 支出 ${decimalMoney(expense, currency)}',
                          ),
                          trailing: Text(
                            decimalMoney(income - expense, currency),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '未结清往来 · 当前全部日期',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            for (final debt in debts)
              Builder(
                builder: (context) {
                  final paid = data.entries
                      .where((e) => e.debtId == debt.id)
                      .fold<int>(0, (s, e) => s + e.amount);
                  if (paid == debt.amount) return const SizedBox.shrink();
                  return Card(
                    child: ListTile(
                      title: Text(
                        '${debt.kind == 'borrow' ? '待偿还' : '待收回'} · ${debt.note.isEmpty ? data.account(debt.accountId).name : debt.note}',
                      ),
                      subtitle: Text(debt.date),
                      trailing: Text(money(debt.amount - paid, currency)),
                    ),
                  );
                },
              ),
          ],
        );
      },
    ),
  );
}
