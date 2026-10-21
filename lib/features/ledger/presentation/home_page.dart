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
                          .contains(search.toLowerCase())),
            )
            .toList();
        final green = Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF81C995)
            : const Color(0xFF237A43);
        final red = Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFFF28B82)
            : const Color(0xFFB3261E);
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
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${month.year} 年 ${month.month} 月',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        metric('收入', income, color: green),
                        metric('支出', expense, color: red),
                        metric('借入', total('borrow')),
                        metric('借出', total('lend')),
                      ],
                    ),
                    const Divider(height: 28),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        metric('结余', income - expense),
                        Expanded(
                          child: InkWell(
                            onTap: () => editBudget(
                              context,
                              ref,
                              monthKey(month),
                              currency,
                              budget,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('预算  ›'),
                                Text(
                                  budget == null
                                      ? '未设置'
                                      : decimalMoney(budget, currency),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '剩余 ${budget == null ? '—' : decimalMoney(budget - expense, currency)}',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: budget != null && expense > budget
                                ? red
                                : null,
                          ),
                    ),
                    if (budget != null && budget > 0) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: (expense / budget).clamp(0, 1),
                          minHeight: 6,
                          color: expense > budget
                              ? red
                              : Theme.of(context).colorScheme.primary,
                          semanticsLabel: '预算使用',
                          semanticsValue:
                              '已使用 ${(expense / budget * 100).toStringAsFixed(0)}%',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '预算已用 ${(expense / budget * 100).toStringAsFixed(0)}%',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (totals.isLoading) const LinearProgressIndicator(),
                    if (totals.hasError) const Text('统计读取失败'),
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
                  tooltip: '下个月',
                  onPressed: () => moveMonth(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
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
                        height: 84,
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
                                  int daily(String kind) => entries
                                      .where(
                                        (e) => e.date == key && e.kind == kind,
                                      )
                                      .fold<int>(0, (s, e) => s + e.amount);
                                  final inc = daily('income'),
                                      out = daily('expense');
                                  Widget amount(
                                    int value,
                                    String sign,
                                    Color color,
                                  ) => Tooltip(
                                    message:
                                        '$key $sign${money(value, currency)}',
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 2,
                                      ),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          '$sign${decimalMoney(value, currency)}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: color,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                  return Semantics(
                                    label: key,
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
                                          color: day == key
                                              ? Theme.of(context)
                                                    .colorScheme
                                                    .primaryContainer
                                              : null,
                                          borderRadius: BorderRadius.circular(
                                            12,
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
                                            const SizedBox(height: 2),
                                            if (inc > 0)
                                              amount(inc, '+', green),
                                            if (out > 0) amount(out, '-', red),
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
            const SizedBox(height: 12),
            ClearableSearch(
              value: search,
              hint: '搜索备注、往来人、分类或账户',
              onChanged: (value) => setState(() => search = value),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: Text(day ?? '整月'),
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
            if (filtered.isEmpty) const EmptyState('暂无账目', '点击“记一笔”添加。'),
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
              '${entry.date} · ${account.name}${entry.targetAccountId == null ? '' : ' → ${data.account(entry.targetAccountId!).name}'}${entry.counterparty.isEmpty ? '' : ' · ${entry.counterparty}'}${entry.note.isEmpty ? '' : '\n${entry.note}'}',
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
