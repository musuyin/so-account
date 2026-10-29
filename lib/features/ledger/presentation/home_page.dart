import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/providers.dart';
import '../../../app/widgets.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/money/money.dart';
import '../../../core/time/business_date.dart';
import '../../../data/database/app_database.dart';
import '../../inventory/presentation/item_form.dart';
import '../domain/entry_kind.dart';
import 'entry_form.dart';
import 'calendar_heatmap.dart';
import 'category_icons.dart';

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
  int limit = 100;
  HomeQuery get query => (
    month: monthKey(month),
    currency: currency,
    day: day,
    kind: kind?.name,
    category: category,
    search: search,
    limit: limit,
  );
  @override
  void setState(VoidCallback fn) {
    final previous = query;
    super.setState(() {
      fn();
      final current = query;
      if (previous.month != current.month ||
          previous.currency != current.currency ||
          previous.day != current.day ||
          previous.kind != current.kind ||
          previous.category != current.category ||
          previous.search != current.search) {
        limit = 100;
      }
    });
  }

  void moveMonth(int delta) => setState(() {
    month = DateTime(month.year, month.month + delta);
    day = null;
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('素帐'),
      actions: [
        TextButton(
          onPressed: () => setState(() {
            month = DateTime(DateTime.now().year, DateTime.now().month);
            day = dateKey(DateTime.now());
          }),
          child: const Text('今天'),
        ),
        DropdownButton<String>(
          value: currency,
          underline: const SizedBox(),
          items: currencies
              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
          onChanged: (v) => setState(() => currency = v!),
        ),
      ],
    ),
    body: QueryView<HomeLedgerView>(
      value: ref.watch(homeLedgerProvider(query)),
      retry: () => ref.invalidate(homeLedgerProvider(query)),
      builder: (view) {
        final data = view.data;
        // Refresh category order without reloading the scoped ledger rows.
        final categoryChoices = AppSnapshot(
          [],
          data.categories,
          [],
          [],
          [],
          [],
          ref.watch(preferencesProvider).asData?.value ?? [],
        ).categories;
        int total(String kind) => view.totals[kind] ?? 0;
        final income = total('income'), expense = total('expense');
        final budget = data.budgets
            .where((b) => b.month == monthKey(month) && b.currency == currency)
            .firstOrNull
            ?.amount;
        final entries = data.entries;
        final filtered = entries;
        final green = calendarIncomeColor(Theme.of(context).brightness);
        final red = calendarExpenseColor(Theme.of(context).brightness);
        final dailyTotals = view.daily;
        final groups = <String, List<Entry>>{};
        for (final entry in filtered) {
          (groups[entry.date] ??= []).add(entry);
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            Card(
              key: const ValueKey('monthly-summary'),
              borderOnForeground: false,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MoneySummary(
                      values: [
                        (
                          label: '收入',
                          amount: decimalMoney(income, currency),
                          color: green,
                        ),
                        (
                          label: '支出',
                          amount: decimalMoney(expense, currency),
                          color: red,
                        ),
                        (
                          label: '结余',
                          amount: decimalMoney(income - expense, currency),
                          color: null,
                        ),
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
              LedgerCalendar(
                month: month,
                currency: currency,
                daily: dailyTotals,
                selected: day,
                onSelected: (value) =>
                    setState(() => day = day == value ? null : value),
              ),
              const CalendarHeatLegend(),
            ],
            const SizedBox(height: 4),
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
                    ...categoryChoices.map(
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
                '${day ?? monthKey(month)} · ${view.count} 笔',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            if (filtered.isEmpty) ...[
              EmptyState(
                view.monthCount == 0 ? '暂无账目' : '没有匹配的账目',
                view.monthCount == 0 ? '点击“记一笔”添加。' : '可清除筛选，查看本月其他账目。',
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
            if (day != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  '$day · $currency · 收入 ${decimalMoney(dailyTotals[day]?['income'] ?? 0, currency)} · 支出 ${decimalMoney(dailyTotals[day]?['expense'] ?? 0, currency)}',
                ),
              ),
            for (final group in groups.entries)
              EntryDayCard(
                date: group.key,
                entries: group.value,
                data: data,
                totals:
                    (view.filteredDaily.isEmpty
                        ? view.daily
                        : view.filteredDaily)[group.key] ??
                    {},
                currency: currency,
                filtered: kind != null || category != null || search.isNotEmpty,
              ),
            if (view.count > entries.length)
              TextButton(
                onPressed: () => setState(() => limit += 100),
                child: const Text('显示更多记录'),
              ),
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

class EntryDayCard extends StatelessWidget {
  const EntryDayCard({
    super.key,
    required this.date,
    required this.entries,
    required this.data,
    required this.totals,
    required this.currency,
    this.filtered = false,
  });
  final String date, currency;
  final List<Entry> entries;
  final AppSnapshot data;
  final Map<String, int> totals;
  final bool filtered;
  @override
  Widget build(BuildContext context) {
    final day = parseDate(date);
    final now = DateTime.now();
    final yesterday = dateKey(DateTime(now.year, now.month, now.day - 1));
    final relative = date == dateKey(now)
        ? ' · 今天'
        : date == yesterday
        ? ' · 昨天'
        : '';
    return Card(
      key: ValueKey('day-group-$date'),
      borderOnForeground: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
            child: Wrap(
              spacing: 8,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${day.month}月${day.day}日$relative · 周${['一', '二', '三', '四', '五', '六', '日'][day.weekday - 1]}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  '${filtered ? '筛选合计 · ' : ''}收 ${decimalMoney(totals['income'] ?? 0, currency)} · 支 ${decimalMoney(totals['expense'] ?? 0, currency)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 12, endIndent: 12),
            EntryTile(entry: entries[i], data: data, grouped: true),
          ],
        ],
      ),
    );
  }
}

class EntryTile extends ConsumerWidget {
  const EntryTile({
    super.key,
    required this.entry,
    required this.data,
    this.grouped = false,
  });
  final bool grouped;
  final Entry entry;
  final AppSnapshot data;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = EntryKind.values.byName(entry.kind);
    final account = data.account(entry.accountId);
    final links = data.links.where((l) => l.entryId == entry.id);
    final content = Column(
      children: [
        ListTile(
          leading: CircleAvatar(
            radius: 16,
            child: Icon(
              kind.needsCategory
                  ? categoryIcon(
                      data.category(entry.categoryId),
                      iconId: AppSnapshot(
                        [],
                        [],
                        [],
                        [],
                        [],
                        [],
                        ref.watch(preferencesProvider).value ??
                            data.preferences,
                      ).categoryIconId(entry.categoryId!),
                    )
                  : kind == EntryKind.transfer
                  ? Icons.swap_horiz
                  : kind.direction > 0
                  ? Icons.south_west
                  : Icons.north_east,
            ),
          ),
          title: LayoutBuilder(
            builder: (context, constraints) {
              final name = Text(
                kind.needsCategory
                    ? data.category(entry.categoryId)
                    : kind.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              );
              final amount = Text(
                '${kind == EntryKind.transfer
                    ? '转出 '
                    : kind.direction > 0
                    ? '+'
                    : '-'}${decimalMoney(entry.amount, account.currency)}',
                style: AppTypography.amount.copyWith(
                  color: kind == EntryKind.income
                      ? calendarIncomeColor(Theme.of(context).brightness)
                      : kind == EntryKind.expense
                      ? calendarExpenseColor(Theme.of(context).brightness)
                      : null,
                ),
              );
              final measure = TextPainter(
                text: TextSpan(
                  text: amount.data,
                  style: DefaultTextStyle.of(context).style.merge(amount.style),
                ),
                textDirection: TextDirection.ltr,
                textScaler: MediaQuery.textScalerOf(context),
              )..layout();
              final stack =
                  constraints.maxWidth <
                  measure.width +
                      MediaQuery.textScalerOf(context).scale(13) * 3 +
                      8;
              measure.dispose();
              return stack
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        name,
                        Align(alignment: Alignment.centerRight, child: amount),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: name),
                        const SizedBox(width: 8),
                        amount,
                      ],
                    );
            },
          ),
          subtitle: Text(
            '${grouped ? '' : '${entry.date} · '}${account.name}${entry.targetAccountId == null ? '' : ' → ${data.account(entry.targetAccountId!).name}'}${entry.counterparty.isEmpty ? '' : ' · ${entry.counterparty}'}${entry.note.isEmpty ? '' : '\n${entry.note}'}',
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
                        item: data.items.firstWhere((i) => i.id == link.itemId),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
    return grouped ? content : Card(borderOnForeground: false, child: content);
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
