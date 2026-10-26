import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/providers.dart';
import '../../../app/widgets.dart';
import '../../../core/money/money.dart';
import '../../../core/time/business_date.dart';
import '../../../data/database/app_database.dart';
import '../data/goals_repository.dart';
import '../data/goals_export.dart';

class GoalsPage extends ConsumerStatefulWidget {
  const GoalsPage({super.key, this.initialCurrency = 'CNY'});
  final String initialCurrency;
  @override
  ConsumerState<GoalsPage> createState() => _GoalsPageState();
}

class _GoalsPageState extends ConsumerState<GoalsPage> {
  bool exporting = false;
  Future<void> export(bool details) async {
    if (exporting) return;
    setState(() => exporting = true);
    await perform(context, () async {
      final csv = await GoalsExport(ref.read(databaseProvider))
          .create(details: details);
      final saved = await ref
          .read(fileDeliveryProvider)
          .save(
            'so-account-goals-${details ? 'details' : 'summary'}-${dateKey(DateTime.now())}.csv',
            Uint8List.fromList(utf8.encode(csv)),
          );
      if (saved && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已保存全部目标数据（含所有币种及状态）')));
      }
    });
    if (mounted) setState(() => exporting = false);
  }

  late String currency = widget.initialCurrency;
  String status = 'active', kind = '', search = '', sort = 'priority';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('心愿'),
      actions: [
        DropdownButton<String>(
          value: currency,
          onChanged: (v) => setState(() => currency = v!),
          items: currencies
              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
        ),

        PopupMenuButton<bool>(
          tooltip: '导出目标数据',
          enabled: !exporting,
          onSelected: export,
          icon: exporting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.file_download_outlined),
          itemBuilder: (_) => const [
            PopupMenuItem(value: false, child: Text('全部目标汇总 CSV')),
            PopupMenuItem(value: true, child: Text('全部攒钱明细 CSV')),
          ],
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => openForm(context, GoalForm(initialCurrency: currency)),
      icon: const Icon(Icons.add),
      label: const Text('新增目标'),
    ),
    body: DataView(
      builder: (data) {
        final totals = <String, int>{};
        for (final row in data.contributions) {
          totals.update(
            row.goalId,
            (value) => value + row.amount,
            ifAbsent: () => row.amount,
          );
        }
        final all = data.goals
            .where(
              (g) => g.currency == currency && (kind.isEmpty || g.kind == kind),
            )
            .toList();
        final active = all.where((g) => g.status == 'active');
        final target = active.fold(0, (int sum, g) => sum + g.target);
        final saved = active.fold(0, (int sum, g) => sum + (totals[g.id] ?? 0));
        final goals =
            all
                .where(
                  (g) =>
                      (status == 'all' || g.status == status) &&
                      '${g.name} ${g.note}'.toLowerCase().contains(
                        search.trim().toLowerCase(),
                      ),
                )
                .toList()
              ..sort((a, b) {
                final value = switch (sort) {
                  'deadline' => (a.deadline ?? '9999-12-31').compareTo(
                    b.deadline ?? '9999-12-31',
                  ),
                  'progress' => ((totals[b.id] ?? 0) / b.target).compareTo(
                    (totals[a.id] ?? 0) / a.target,
                  ),
                  _ => b.priority.compareTo(a.priority),
                };
                return value != 0 ? value : b.createdAt.compareTo(a.createdAt);
              });
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
          children: [
            Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<String>(
                  value: sort,
                  onChanged: (v) => setState(() => sort = v!),
                  items: const [
                    DropdownMenuItem(value: 'priority', child: Text('优先级排序')),
                    DropdownMenuItem(value: 'deadline', child: Text('截止日期排序')),
                    DropdownMenuItem(value: 'progress', child: Text('进度排序')),
                  ],
                ),
              ],
            ),
            Card(
              borderOnForeground: false,
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('进行中 · ${active.length} 个目标'),
                    const SizedBox(height: 8),
                    Text(
                      decimalMoney(saved, currency),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text('已记录进度 / 目标 ${decimalMoney(target, currency)}'),
                    const SizedBox(height: 8),
                    const Text('进度手动记录，不锁定账户资金，不重复计入资产或收支。'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            ClearableSearch(
              value: search,
              hint: '搜索目标或备注',
              onChanged: (v) => setState(() => search = v),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in {'': '全部类型', ...goalKinds}.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: kind == entry.key,
                    onSelected: (_) => setState(() => kind = entry.key),
                  ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in {...goalStatuses, 'all': '全部状态'}.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: status == entry.key,
                    onSelected: (_) => setState(() => status = entry.key),
                  ),
              ],
            ),
            if (goals.isEmpty)
              const EmptyState('还没有符合条件的目标', '添加一个心愿，或为下一次旅行开始攒钱。'),
            for (final goal in goals)
              Card(
                borderOnForeground: false,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => openForm(context, GoalDetailPage(id: goal.id)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: GoalProgress(
                      goal: goal,
                      saved: totals[goal.id] ?? 0,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class GoalProgress extends StatelessWidget {
  const GoalProgress({super.key, required this.goal, required this.saved});
  final WishGoal goal;
  final int saved;
  @override
  Widget build(BuildContext context) {
    final remaining = (goal.target - saved).clamp(0, maximumGoalAmount);
    final days = goal.deadline == null
        ? null
        : goalDaysLeft(goal.deadline!, DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.savings_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                goal.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(goalKinds[goal.kind]!),
            Text(goalStatuses[goal.status]!),
            Text(goalPriorities[goal.priority]!),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '${decimalMoney(saved, goal.currency)} / ${decimalMoney(goal.target, goal.currency)}',
        ),
        const SizedBox(height: 8),
        Semantics(
          label: '目标进度',
          value: '${(saved * 100 / goal.target).round()}%',
          child: LinearProgressIndicator(
            value: (saved / goal.target).clamp(0.0, 1.0),
            minHeight: 8,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          remaining == 0
              ? '已达到目标${saved > goal.target ? ' · 超出 ${decimalMoney(saved - goal.target, goal.currency)}' : ''}'
              : '还差 ${decimalMoney(remaining, goal.currency)}',
        ),
        if (days != null) ...[
          const SizedBox(height: 4),
          Text(
            '${goal.deadline} · ${days < 0
                ? '已逾期 ${-days} 天'
                : days == 0
                ? '今天截止'
                : '剩余 $days 天'}',
            style: TextStyle(
              color: days < 0 && goal.status == 'active'
                  ? Theme.of(context).colorScheme.error
                  : null,
            ),
          ),
          if (goal.status == 'active' && remaining > 0 && days >= 0)
            Text(
              '按期完成，每天记录 ${decimalMoney(goalDailyAmount(goal, saved, DateTime.now()), goal.currency)}',
            ),
        ],
      ],
    );
  }
}

class GoalForm extends ConsumerStatefulWidget {
  const GoalForm({super.key, this.goal, this.initialCurrency = 'CNY'});
  final WishGoal? goal;
  final String initialCurrency;
  @override
  ConsumerState<GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends ConsumerState<GoalForm> {
  late final name = TextEditingController(text: widget.goal?.name);
  late final target = TextEditingController(
    text: widget.goal == null
        ? ''
        : decimalMoney(widget.goal!.target, widget.goal!.currency),
  );
  late final note = TextEditingController(text: widget.goal?.note);
  final initial = TextEditingController();
  late String kind = widget.goal?.kind ?? 'wish',
      currency = widget.goal?.currency ?? widget.initialCurrency;
  late String? deadline = widget.goal?.deadline;
  late int priority = widget.goal?.priority ?? 1;
  bool saving = false;
  @override
  void dispose() {
    name.dispose();
    target.dispose();
    note.dispose();
    initial.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DataView(
    builder: (data) {
      final locked = data.contributions.any((r) => r.goalId == widget.goal?.id);
      return FormFrame(
        title: widget.goal == null ? '新增目标' : '编辑目标',
        saving: saving,
        onSave: () async {
          if (saving) return;
          setState(() => saving = true);
          final ok = await perform(context, () async {
            await ref
                .read(goalsProvider)
                .save(
                  id: widget.goal?.id,
                  name: name.text,
                  kind: kind,
                  currency: currency,
                  target: parseMoney(target.text, currency),
                  deadline: deadline,
                  priority: priority,
                  note: note.text,
                  initialSaved:
                      widget.goal == null && initial.text.trim().isNotEmpty
                      ? parseMoney(initial.text, currency)
                      : 0,
                );
          });
          if (mounted && context.mounted) {
            setState(() => saving = false);
            if (ok) Navigator.pop(context);
          }
        },
        children: [
          Wrap(
            spacing: 12,
            children: [
              for (final entry in goalKinds.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: kind == entry.key,
                  onSelected: saving
                      ? null
                      : (_) => setState(() => kind = entry.key),
                ),
            ],
          ),
          TextField(
            controller: name,
            maxLength: 100,
            decoration: const InputDecoration(labelText: '目标名称'),
          ),
          DropdownButtonFormField<String>(
            initialValue: currency,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: '币种',
              helperText: locked ? '已有攒钱记录，币种不可更改' : null,
            ),
            items: currencies
                .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                .toList(),
            onChanged: locked || saving
                ? null
                : (v) => setState(() => currency = v!),
          ),
          TextField(
            controller: target,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: '目标金额'),
          ),
          if (widget.goal == null)
            TextField(
              controller: initial,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: '已经攒下（选填）',
                helperText: '仅记录进度，不改变账户余额',
              ),
            ),
          DropdownButtonFormField<int>(
            initialValue: priority,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '优先级'),
            items: goalPriorities.entries
                .map(
                  (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                )
                .toList(),
            onChanged: saving ? null : (v) => setState(() => priority = v!),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('截止日期（选填）'),
            subtitle: Text(deadline ?? '不设置'),
            trailing: deadline == null
                ? const Icon(Icons.calendar_today_outlined)
                : IconButton(
                    tooltip: '清除截止日期',
                    onPressed: saving
                        ? null
                        : () => setState(() => deadline = null),
                    icon: const Icon(Icons.close),
                  ),
            onTap: saving
                ? null
                : () async {
                    final value = await pickGoalDate(context, deadline);
                    if (value != null && mounted) {
                      setState(() => deadline = dateKey(value));
                    }
                  },
          ),
          TextField(
            controller: note,
            maxLength: 2000,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: '备注（选填）'),
          ),
        ],
      );
    },
  );
}

Future<DateTime?> pickGoalDate(
  BuildContext context,
  String? current, {
  bool future = true,
}) {
  final first = DateTime(1900),
      last = future ? DateTime(2100, 12, 31) : DateTime.now();
  var initial = current == null ? DateTime.now() : parseDate(current);
  if (initial.isBefore(first)) initial = first;
  if (initial.isAfter(last)) initial = last;
  return showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: first,
    lastDate: last,
  );
}

class GoalDetailPage extends ConsumerStatefulWidget {
  const GoalDetailPage({super.key, required this.id});
  final String id;
  @override
  ConsumerState<GoalDetailPage> createState() => _GoalDetailState();
}

class _GoalDetailState extends ConsumerState<GoalDetailPage> {
  bool busy = false;
  int limit = 50;
  Future<void> action(Future<void> Function() work) async {
    if (busy) return;
    setState(() => busy = true);
    await perform(context, work);
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => DataView(
    builder: (data) {
      final goal = data.goals.where((g) => g.id == widget.id).firstOrNull;
      if (goal == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('目标')),
          body: const EmptyState('目标已删除', '返回列表查看其他目标。'),
        );
      }
      final records =
          data.contributions.where((r) => r.goalId == goal.id).toList()
            ..sort((a, b) {
              final day = b.date.compareTo(a.date);
              return day != 0 ? day : b.createdAt.compareTo(a.createdAt);
            });
      final saved = goalSaved(goal.id, records);
      return Scaffold(
        appBar: AppBar(
          title: Text('心愿 · ${goal.currency}'),
          actions: [
            IconButton(
              tooltip: '编辑目标',
              onPressed: busy
                  ? null
                  : () => openForm(context, GoalForm(goal: goal)),
              icon: const Icon(Icons.edit_outlined),
            ),
            PopupMenuButton<String>(
              enabled: !busy,
              tooltip: '更多操作',
              onSelected: (value) async {
                if (value == 'delete') {
                  final confirmed = await confirm(
                    context,
                    '删除目标？',
                    '将删除此目标和全部攒钱记录，不影响账户与交易。',
                  );
                  if (!confirmed || !mounted || !context.mounted) return;
                  setState(() => busy = true);
                  final ok = await perform(
                    context,
                    () => ref.read(goalsProvider).delete(goal.id),
                  );
                  if (mounted && context.mounted) {
                    setState(() => busy = false);
                    if (ok) Navigator.pop(context);
                  }
                } else {
                  await action(
                    () => ref.read(goalsProvider).setStatus(goal.id, value),
                  );
                }
              },
              itemBuilder: (_) => [
                if (goal.status != 'archived')
                  const PopupMenuItem(value: 'archived', child: Text('归档目标')),
                const PopupMenuItem(value: 'delete', child: Text('删除目标')),
              ],
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            GoalProgress(goal: goal, saved: saved),
            if (goal.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(goal.note),
              ),
            const SizedBox(height: 12),
            const Text('进度独立记录，不影响账户、交易或预算。实际购买请另行记账。'),
            const SizedBox(height: 10),
            if (goal.status == 'active') ...[
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: busy
                        ? null
                        : () => openForm(context, ContributionForm(goal: goal)),
                    icon: const Icon(Icons.add),
                    label: const Text('存入'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy || saved == 0
                        ? null
                        : () => openForm(
                            context,
                            ContributionForm(goal: goal, withdraw: true),
                          ),
                    icon: const Icon(Icons.remove),
                    label: const Text('取出'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: busy || goal.kind == 'saving' && saved < goal.target
                    ? null
                    : () => action(
                        () => ref
                            .read(goalsProvider)
                            .setStatus(goal.id, 'completed'),
                      ),
                icon: const Icon(Icons.check_circle_outline),
                label: Text(goal.kind == 'wish' ? '标记已实现' : '完成攒钱目标'),
              ),
            ] else
              FilledButton.tonalIcon(
                onPressed: busy
                    ? null
                    : () => action(
                        () => ref
                            .read(goalsProvider)
                            .setStatus(goal.id, 'active'),
                      ),
                icon: const Icon(Icons.replay),
                label: const Text('恢复进行中'),
              ),
            const SizedBox(height: 24),
            Text(
              '攒钱记录 · ${records.length} 笔',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (records.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text('尚未记录进度，随时可以从一小笔开始。'),
              ),
            for (final row in records.take(limit))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  row.amount > 0 ? Icons.south_west : Icons.north_east,
                ),
                title: Text(
                  '${row.amount > 0 ? '+' : '−'} ${decimalMoney(row.amount.abs(), goal.currency)}',
                ),
                subtitle: Text(
                  '${row.date}${row.note.isEmpty ? '' : ' · ${row.note}'}',
                ),
                trailing: goal.status != 'active'
                    ? null
                    : IconButton(
                        tooltip: '删除攒钱记录',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: busy
                            ? null
                            : () async {
                                final confirmed = await confirm(
                                  context,
                                  '删除记录？',
                                  '删除后会重新计算进度；若导致之后的取出超过已攒金额，则无法删除。',
                                );
                                if (confirmed && mounted) {
                                  await action(
                                    () => ref
                                        .read(goalsProvider)
                                        .deleteContribution(row.id),
                                  );
                                }
                              },
                      ),
              ),
            if (records.length > limit)
              TextButton(
                onPressed: () => setState(() => limit += 50),
                child: const Text('显示更多记录'),
              ),
          ],
        ),
      );
    },
  );
}

class ContributionForm extends ConsumerStatefulWidget {
  const ContributionForm({
    super.key,
    required this.goal,
    this.withdraw = false,
  });
  final WishGoal goal;
  final bool withdraw;
  @override
  ConsumerState<ContributionForm> createState() => _ContributionState();
}

class _ContributionState extends ConsumerState<ContributionForm> {
  final amount = TextEditingController(), note = TextEditingController();
  String date = dateKey(DateTime.now());
  bool saving = false;
  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormFrame(
    title: widget.withdraw ? '取出进度' : '存入进度',
    saving: saving,
    currency: widget.goal.currency,
    onSave: () async {
      if (saving) return;
      setState(() => saving = true);
      final ok = await perform(context, () async {
        final value = parseMoney(amount.text, widget.goal.currency);
        await ref
            .read(goalsProvider)
            .contribute(
              goalId: widget.goal.id,
              amount: widget.withdraw ? -value : value,
              date: date,
              note: note.text,
              expectedCurrency: widget.goal.currency,
            );
      });
      if (mounted && context.mounted) {
        setState(() => saving = false);
        if (ok) Navigator.pop(context);
      }
    },
    children: [
      Text(widget.goal.name, style: Theme.of(context).textTheme.titleLarge),
      TextField(
        controller: amount,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: '金额'),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('日期'),
        subtitle: Text(date),
        trailing: const Icon(Icons.calendar_today_outlined),
        onTap: saving
            ? null
            : () async {
                final value = await pickGoalDate(context, date, future: false);
                if (value != null && mounted) {
                  setState(() => date = dateKey(value));
                }
              },
      ),
      TextField(
        controller: note,
        maxLength: 500,
        decoration: const InputDecoration(labelText: '备注（选填）'),
      ),
      const Text('这是一笔目标进度记录，不会执行转账或改变账户余额。'),
    ],
  );
}
