import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/providers.dart';
import '../../../app/widgets.dart';
import '../../../core/money/money.dart';
import '../../../core/time/business_date.dart';
import '../../../data/database/app_database.dart';
import '../../inventory/presentation/item_form.dart';
import '../domain/entry_kind.dart';
import 'entry_form.dart';
import 'calendar_heatmap.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});
  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  String? day, category;
  EntryKind? kind;
  String currency = 'CNY', search = '';
  bool calendarExpanded = true;
  void moveMonth(int delta) => setState(() {
    month = DateTime(month.year, month.month + delta);
    day = null;
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('素帐'),
      actions: [
        DropdownButton<String>(
          value: currency,
          underline: const SizedBox(),
          items: currencies
              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
          onChanged: (v) => setState(() => currency = v!),
        ),
        TextButton(
          onPressed: () => setState(() {
            month = DateTime(DateTime.now().year, DateTime.now().month);
            day = dateKey(DateTime.now());
          }),
          child: const Text('今天'),
        ),
      ],
    ),
    body: DataView(
      builder: (data) {
        final totals = ref.watch(monthlyProvider(monthKey(month)));
        int total(String kind) =>
            (totals.value ?? [])
                .where((t) => t.currency == currency && t.kind == kind)
                .firstOrNull
                ?.amount ??
            0;
        final income = total('income'), expense = total('expense');
        final budget = data.budgets
            .where((b) => b.month == monthKey(month) && b.currency == currency)
            .firstOrNull
            ?.amount;
        final entries =
            data.entries
                .where(
                  (e) =>
                      e.date.startsWith(monthKey(month)) &&
                      data.account(e.accountId).currency == currency,
                )
                .toList()
              ..sort(
                (a, b) => a.date == b.date
                    ? b.createdAt.compareTo(a.createdAt)
                    : b.date.compareTo(a.date),
              );
        final filtered = entries
            .where(
              (e) =>
                  (day == null || e.date == day) &&
                  (kind == null || e.kind == kind!.name) &&
                  (category == null || e.categoryId == category) &&
                  (search.isEmpty ||
                      '${e.note} ${e.counterparty} ${data.category(e.categoryId)} ${data.account(e.accountId).name}'
                          .toLowerCase()
                          .contains(search.trim().toLowerCase())),
            )
            .toList();
        final green = calendarIncomeColor(Theme.of(context).brightness);
        final red = calendarExpenseColor(Theme.of(context).brightness);
        Widget metric(String label, int amount, {Color? color}) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  decimalMoney(amount, currency),
                  style: TextStyle(fontWeight: FontWeight.w600, color: color),
                ),
              ),
            ],
          ),
        );
        final dailyTotals = <String, Map<String, int>>{};
        for (final entry in entries) {
          if (entry.kind == 'income' || entry.kind == 'expense') {
            final values = dailyTotals.putIfAbsent(entry.date, () => {});
            values.update(
              entry.kind,
              (v) => v + entry.amount,
              ifAbsent: () => entry.amount,
            );
          }
        }
        final maximumNet = dailyTotals.values.fold<int>(0, (maximum, values) {
          final value = ((values['income'] ?? 0) - (values['expense'] ?? 0))
              .abs();
          return value > maximum ? value : maximum;
        });
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            Card(
              key: const ValueKey('monthly-summary'),
              borderOnForeground: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        metric('收入', income, color: green),
                        metric('支出', expense, color: red),
                        metric('结余', income - expense),
                      ],
                    ),
                    const Divider(height: 6),
                    InkWell(
                      onTap: () => editBudget(
                        context,
                        ref,
                        monthKey(month),
                        currency,
                        budget,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Wrap(
                          spacing: 16,
                          runSpacing: 4,
                          children: [
                            Text(
                              budget == null
                                  ? '预算：未设置  ›'
                                  : '预算 ${decimalMoney(budget, currency)}  ›',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (budget != null)
                              Text(
                                '剩余 ${decimalMoney(budget - expense, currency)}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: expense > budget ? red : null,
                                    ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (budget != null && budget > 0)
                      LinearProgressIndicator(
                        value: (expense / budget).clamp(0, 1),
                        minHeight: 3,
                        color: expense > budget ? red : null,
                        semanticsLabel:
                            '预算已使用 ${(expense / budget * 100).toStringAsFixed(0)}%',
                      ),
                    if (total('borrow') != 0 || total('lend') != 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '借入 ${decimalMoney(total('borrow'), currency)} · 借出 ${decimalMoney(total('lend'), currency)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    if (totals.isLoading) const LinearProgressIndicator(),
                    if (totals.hasError)
                      TextButton(
                        onPressed: () =>
                            ref.invalidate(monthlyProvider(monthKey(month))),
                        child: const Text('统计读取失败，点击重试'),
                      ),
                  ],
                ),
              ),
            ),
            Row(
              children: [
                IconButton(
                  tooltip: '上个月',
                  onPressed: () => moveMonth(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    '${month.year} 年 ${month.month} 月',
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  tooltip: calendarExpanded ? '收起月历' : '展开月历',
                  onPressed: () =>
                      setState(() => calendarExpanded = !calendarExpanded),
                  icon: Icon(
                    calendarExpanded
                        ? Icons.unfold_less
                        : Icons.calendar_month_outlined,
                  ),
                ),
                IconButton(
                  tooltip: '下个月',
                  onPressed: () => moveMonth(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            if (calendarExpanded) ...[
              Row(
                children: [
                  for (final label in ['一', '二', '三', '四', '五', '六', '日'])
                    Expanded(child: Center(child: Text(label))),
                ],
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final offset = month.weekday - 1,
                      count = DateTime(month.year, month.month + 1, 0).day;
                  return Wrap(
                    children: [
                      for (var i = 0; i < ((offset + count + 6) ~/ 7) * 7; i++)
                        SizedBox(
                          width: constraints.maxWidth / 7,
                          height:
                              (MediaQuery.textScalerOf(context).scale(14) *
                                          1.2 +
                                      MediaQuery.textScalerOf(context)
                                              .scale(12) *
                                          2 *
                                          1.2 +
                                      10)
                                  .clamp(48, double.infinity),
                          child: i < offset || i >= offset + count
                              ? null
                              : Builder(
                                  builder: (context) {
                                    final key = dateKey(
                                      DateTime(
                                        month.year,
                                        month.month,
                                        i - offset + 1,
                                      ),
                                    );
                                    int daily(String kind) =>
                                        dailyTotals[key]?[kind] ?? 0;
                                    final inc = daily('income'),
                                        out = daily('expense');
                                    Widget amount(
                                      int value,
                                      String sign,
                                      Color color,
                                    ) => Tooltip(
                                      message:
                                          '$key $sign${decimalMoney(value, currency)}',
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 2,
                                        ),
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            '$sign${decimalMoney(value, currency)}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              height: 1.2,
                                              color: color,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                    return Semantics(
                                      key: ValueKey('calendar-$key'),
                                      label:
                                          '$key，收入 ${decimalMoney(inc, currency)}，支出 ${decimalMoney(out, currency)}，净额 ${decimalMoney(inc - out, currency)}',
                                      selected: day == key,
                                      button: true,
                                      child: InkWell(
                                        onTap: () => setState(
                                          () => day = day == key ? null : key,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        child: Container(
                                          margin: const EdgeInsets.all(2),
                                          decoration: BoxDecoration(
                                            color: calendarHeatColor(
                                              Theme.of(context).colorScheme,
                                              inc,
                                              out,
                                              maximumNet,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          foregroundDecoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border:
                                                day == key ||
                                                    key ==
                                                        dateKey(DateTime.now())
                                                ? Border.all(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .primary,
                                                    width: day == key ? 2 : 1,
                                                  )
                                                : null,
                                          ),
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                '${i - offset + 1}',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  height: 1.2,
                                                  fontWeight:
                                                      key ==
                                                          dateKey(
                                                            DateTime.now(),
                                                          )
                                                      ? FontWeight.w700
                                                      : FontWeight.w500,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              if (inc > 0 || out > 0) ...[
                                                amount(out, '-', red),
                                                amount(inc, '+', green),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                    ],
                  );
                },
              ),
              const CalendarHeatLegend(),
            ],
            const SizedBox(height: 6),
            ClearableSearch(
              value: search,
              hint: '搜索备注、往来人、分类或账户',
              onChanged: (value) => setState(() => search = value),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (day != null)
                  FilterChip(
                    label: Text(day!),
                    selected: day != null,
                    onSelected: (_) => setState(() => day = null),
                  ),
                PopupMenuButton<String>(
                  onSelected: (v) => setState(
                    () => kind = v.isEmpty ? null : EntryKind.values.byName(v),
                  ),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: '', child: Text('全部类型')),
                    ...EntryKind.values.map(
                      (k) => PopupMenuItem(value: k.name, child: Text(k.label)),
                    ),
                  ],
                  child: Chip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(kind?.label ?? '全部类型'),
                        const Icon(Icons.arrow_drop_down, size: 16),
                      ],
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) =>
                      setState(() => category = v.isEmpty ? null : v),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: '', child: Text('全部分类')),
                    ...data.categories.map(
                      (c) => PopupMenuItem(
                        value: c.id,
                        child: Text(
                          '${c.name} · ${c.kind == 'income' ? '收入' : '支出'}',
                        ),
                      ),
                    ),
                  ],
                  child: Chip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          category == null ? '全部分类' : data.category(category),
                        ),
                        const Icon(Icons.arrow_drop_down, size: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              key: const ValueKey('ledger-list-heading'),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '${day ?? monthKey(month)} · ${filtered.length} 笔',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            if (filtered.isEmpty) ...[
              EmptyState(
                entries.isEmpty ? '暂无账目' : '没有匹配的账目',
                entries.isEmpty ? '点击“记一笔”添加。' : '可清除筛选，查看本月其他账目。',
              ),
              if (day != null ||
                  kind != null ||
                  category != null ||
                  search.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() {
                    day = null;
                    kind = null;
                    category = null;
                    search = '';
                  }),
                  child: const Text('清除筛选'),
                ),
            ],
            for (final entry in filtered) EntryTile(entry: entry, data: data),
          ],
        );
      },
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => openForm(
        context,
        EntryForm(
          initialDate: day == null ? null : parseDate(day!),
          initialCurrency: currency,
        ),
      ),
      icon: const Icon(Icons.add),
      label: const Text('记一笔'),
    ),
  );
}

class EntryTile extends ConsumerWidget {
  const EntryTile({super.key, required this.entry, required this.data});
  final Entry entry;
  final AppSnapshot data;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = EntryKind.values.byName(entry.kind);
    final account = data.account(entry.accountId);
    final links = data.links.where((l) => l.entryId == entry.id);
    return Card(
      borderOnForeground: false,
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              radius: 16,
              child: Icon(
                kind.direction > 0 ? Icons.south_west : Icons.north_east,
              ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    kind.needsCategory
                        ? data.category(entry.categoryId)
                        : kind.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${kind.direction > 0 ? '+' : '-'}${decimalMoney(entry.amount, account.currency)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Text(
              '${entry.date} · ${account.name}${entry.targetAccountId == null ? '' : ' → ${data.account(entry.targetAccountId!).name}'}${entry.counterparty.isEmpty ? '' : ' · ${entry.counterparty}'}${entry.note.isEmpty ? '' : '\n${entry.note}'}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: PopupMenuButton<String>(
              tooltip: '账目操作',
              onSelected: (action) async {
                if (action == 'item') {
                  await openForm(
                    context,
                    EntryForm(entry: entry, initialRecordItem: true),
                  );
                } else if (await confirm(context, '删除这笔账目？', '关联会解除，物品仍保留。') &&
                    context.mounted) {
                  await perform(
                    context,
                    () => ref.read(ledgerProvider).deleteEntry(entry.id),
                  );
                }
              },
              itemBuilder: (_) => [
                if (kind == EntryKind.expense)
                  const PopupMenuItem(value: 'item', child: Text('记物')),
                const PopupMenuItem(value: 'delete', child: Text('删除账目')),
              ],
            ),
            onTap: () => openForm(context, EntryForm(entry: entry)),
          ),
          if (links.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final link in links)
                    ActionChip(
                      label: Text(
                        data.items.firstWhere((i) => i.id == link.itemId).name,
                      ),
                      avatar: const Icon(Icons.inventory_2_outlined, size: 16),
                      onPressed: () => openForm(
                        context,
                        ItemForm(
                          item: data.items.firstWhere(
                            (i) => i.id == link.itemId,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> editBudget(
  BuildContext context,
  WidgetRef ref,
  String month,
  String currency,
  int? current,
) async {
  final controller = TextEditingController(
    text: current == null ? '' : decimalMoney(current, currency),
  );
  String? error;
  final input = await showDialog<int>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        void submit() {
          try {
            final value = parseMoney(controller.text, currency);
            Navigator.pop(context, value);
          } on FormatException catch (e) {
            setState(() => error = e.message);
          }
        }

        return AlertDialog(
          title: Text('$month 预算 · $currency'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => submit(),
            onChanged: (_) {
              if (error != null) setState(() => error = null);
            },
            decoration: InputDecoration(labelText: '预算金额', errorText: error),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(onPressed: submit, child: const Text('保存')),
          ],
        );
      },
    ),
  );
  if (input != null && context.mounted) {
    await perform(
      context,
      () => ref.read(ledgerProvider).setBudget(month, currency, input),
    );
  }
  // Dialog exit animations still reference its controller; disposal is deferred.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  controller.dispose();
}
