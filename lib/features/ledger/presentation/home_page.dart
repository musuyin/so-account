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
  void moveMonth(int delta) => setState(() {
    month = DateTime(month.year, month.month + delta);
    day = null;
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('拾账', style: TextStyle(fontWeight: FontWeight.w800)),
      actions: [
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
        final rows = totals.value ?? [];
        final income =
            rows
                .where((t) => t.currency == currency && t.kind == 'income')
                .firstOrNull
                ?.amount ??
            0;
        final expense =
            rows
                .where((t) => t.currency == currency && t.kind == 'expense')
                .firstOrNull
                ?.amount ??
            0;
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
                (a, b) => b.date.compareTo(a.date) == 0
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
                      '${e.note} ${data.category(e.categoryId)} ${data.account(e.accountId).name}'
                          .toLowerCase()
                          .contains(search.toLowerCase())),
            )
            .toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '把日子，记清楚。',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
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
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${month.year} 年 ${month.month} 月 · 结余',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      decimalMoney(income - expense, currency),
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '收入  ${decimalMoney(income, currency)}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '支出  ${decimalMoney(expense, currency)}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.tertiary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => editBudget(
                        context,
                        ref,
                        monthKey(month),
                        currency,
                        budget,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          budget == null
                              ? '设置本月预算  ›'
                              : '预算 ${decimalMoney(budget, currency)} · 剩余 ${decimalMoney(budget - expense, currency)}  ›',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                    if (totals.isLoading) const LinearProgressIndicator(),
                    if (totals.hasError) const Text('统计读取失败，请重新打开本页'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
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
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: '下个月',
                  onPressed: () => moveMonth(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            Row(
              children: [
                for (final label in ['一', '二', '三', '四', '五', '六', '日'])
                  Expanded(
                    child: Center(
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final offset = month.weekday - 1;
                final count = DateTime(month.year, month.month + 1, 0).day;
                return Wrap(
                  children: [
                    for (var i = 0; i < ((offset + count + 6) ~/ 7) * 7; i++)
                      SizedBox(
                        width: constraints.maxWidth / 7,
                        height: 58,
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
                                  final daily = entries.where(
                                    (e) => e.date == key,
                                  );
                                  final selected = day == key;
                                  return Semantics(
                                    label: key,
                                    selected: selected,
                                    button: true,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(14),
                                      onTap: () => setState(
                                        () => day = selected ? null : key,
                                      ),
                                      child: Container(
                                        margin: const EdgeInsets.all(2),
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? Theme.of(context)
                                                    .colorScheme
                                                    .primaryContainer
                                              : null,
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          border: key == dateKey(DateTime.now())
                                              ? Border.all(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary,
                                                )
                                              : null,
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text('${i - offset + 1}'),
                                            const SizedBox(height: 4),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                if (daily.any(
                                                  (e) => e.kind == 'income',
                                                ))
                                                  _dot(
                                                    Theme.of(context)
                                                        .colorScheme
                                                        .secondary,
                                                  ),
                                                if (daily.any(
                                                  (e) => e.kind == 'expense',
                                                ))
                                                  _dot(
                                                    Theme.of(context)
                                                        .colorScheme
                                                        .tertiary,
                                                  ),
                                                if (daily.any(
                                                  (e) => ![
                                                    'income',
                                                    'expense',
                                                  ].contains(e.kind),
                                                ))
                                                  _dot(
                                                    Theme.of(context)
                                                        .colorScheme
                                                        .primary,
                                                  ),
                                              ],
                                            ),
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
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                hintText: '搜索备注、分类或账户',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => search = v),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilterChip(
                  label: Text(day == null ? '整月' : day!),
                  selected: day != null,
                  onSelected: (_) => setState(() => day = null),
                ),
                PopupMenuButton<EntryKind?>(
                  onSelected: (v) => setState(() => kind = v),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: null, child: Text('全部类型')),
                    ...EntryKind.values.map(
                      (v) => PopupMenuItem(value: v, child: Text(v.label)),
                    ),
                  ],
                  child: Chip(label: Text('${kind?.label ?? '全部类型'} ▾')),
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
                    label: Text(
                      '${category == null ? '全部分类' : data.category(category)} ▾',
                    ),
                  ),
                ),
              ],
            ),
            if (kind != null)
              TextButton(
                onPressed: () => setState(() => kind = null),
                child: const Text('清除类型筛选'),
              ),
            if (filtered.isEmpty)
              const EmptyState('这一天，还留着空白', '点“记一笔”，把生活里的小事记下来。'),
            for (final entry in filtered) EntryTile(entry: entry, data: data),
          ],
        );
      },
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => openForm(
        context,
        EntryForm(initialDate: day == null ? null : parseDate(day!)),
      ),
      icon: const Icon(Icons.add),
      label: const Text('记一笔'),
    ),
  );
  Widget _dot(Color color) => Container(
    width: 4,
    height: 4,
    margin: const EdgeInsets.symmetric(horizontal: 1),
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              child: Icon(
                kind.direction > 0 ? Icons.south_west : Icons.north_east,
              ),
            ),
            title: Text(
              kind.needsCategory ? data.category(entry.categoryId) : kind.label,
            ),
            subtitle: Text(
              '${entry.date} · ${account.name}${entry.targetAccountId == null ? '' : ' → ${data.account(entry.targetAccountId!).name}'}${entry.note.isEmpty ? '' : '\n${entry.note}'}',
            ),
            trailing: Text(
              '${kind.direction > 0 ? '+' : '-'}${decimalMoney(entry.amount, account.currency)}',
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
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (kind == EntryKind.expense)
                TextButton.icon(
                  onPressed: () =>
                      openForm(context, ItemForm(initialEntry: entry)),
                  icon: const Icon(Icons.add_box_outlined, size: 18),
                  label: const Text('记物'),
                ),
              IconButton(
                tooltip: '删除账目',
                onPressed: () async {
                  if (await confirm(context, '删除这笔账目？', '关联会解除，物品仍保留。') &&
                      context.mounted) {
                    await perform(
                      context,
                      () => ref.read(ledgerProvider).deleteEntry(entry.id),
                    );
                  }
                },
                icon: const Icon(Icons.delete_outline, size: 20),
              ),
            ],
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
  final input = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('$month 预算 · $currency'),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: '预算金额'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  if (input != null && context.mounted) {
    await perform(
      context,
      () => ref
          .read(ledgerProvider)
          .setBudget(month, currency, parseMoney(input, currency)),
    );
  }
  // Dialog exit animations still reference its controller; disposal is deferred.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  controller.dispose();
}
