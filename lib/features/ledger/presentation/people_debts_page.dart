import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets.dart';
import '../../../core/money/money.dart';
import '../domain/debt_relationship.dart';
import '../domain/entry_kind.dart';
import 'entry_form.dart';

class PeopleDebtsPage extends ConsumerStatefulWidget {
  const PeopleDebtsPage({super.key});
  @override
  ConsumerState<PeopleDebtsPage> createState() => _PeopleDebtsPageState();
}

class _PeopleDebtsPageState extends ConsumerState<PeopleDebtsPage> {
  String currency = 'CNY';
  bool includeSettled = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('人员往来')),
    body: DataView(
      builder: (data) {
        final groups = PersonDebtSummary.group(data.entries, data.accounts)
            .where(
              (g) =>
                  g.currency == currency &&
                  (includeSettled || g.receivable > 0 || g.payable > 0),
            )
            .toList();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<String>(
                  value: currency,
                  items: [
                    for (final value in currencies)
                      DropdownMenuItem(value: value, child: Text(value)),
                  ],
                  onChanged: (value) => setState(() => currency = value!),
                ),
                FilterChip(
                  label: const Text('包含已结清'),
                  selected: includeSettled,
                  onSelected: (value) => setState(() => includeSettled = value),
                ),
              ],
            ),
            Wrap(
              spacing: 12,
              children: [
                for (final kind in [EntryKind.borrow, EntryKind.lend])
                  FilledButton.tonalIcon(
                    onPressed: () =>
                        openForm(context, EntryForm(initialKind: kind)),
                    icon: const Icon(Icons.add),
                    label: Text(kind.label),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '待收回 ${money(groups.fold(0, (sum, g) => sum + g.receivable), currency)}',
            ),
            Text(
              '待偿还 ${money(groups.fold(0, (sum, g) => sum + g.payable), currency)}',
            ),
            if (groups.isEmpty)
              const EmptyState('暂无人员往来', '借入、借出时填写往来人，分笔记录和结算。'),
            for (final group in groups)
              Card(
                child: ExpansionTile(
                  title: Text(group.name.isEmpty ? '未注明往来人' : group.name),
                  subtitle: Text(
                    '待收回 ${money(group.receivable, currency)} · 待偿还 ${money(group.payable, currency)}',
                  ),
                  children: [
                    for (final debt in group.debts.where(
                      (e) =>
                          includeSettled || debtRemaining(e, data.entries) > 0,
                    ))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                '${debt.kind == 'borrow' ? '借入' : '借出'} ${money(debt.amount, currency)}',
                              ),
                              subtitle: Text(
                                '${debt.date} · ${data.account(debt.accountId).name}\n剩余 ${money(debtRemaining(debt, data.entries), currency)}${debt.note.isEmpty ? '' : '\n${debt.note}'}',
                              ),
                              onTap: () =>
                                  openForm(context, EntryForm(entry: debt)),
                            ),
                            if (debtRemaining(debt, data.entries) > 0)
                              TextButton(
                                onPressed: () => openForm(
                                  context,
                                  EntryForm(
                                    initialKind: debt.kind == 'borrow'
                                        ? EntryKind.repay
                                        : EntryKind.collect,
                                    initialDebt: debt,
                                  ),
                                ),
                                child: Text(
                                  debt.kind == 'borrow' ? '偿还借入' : '收回借出',
                                ),
                              ),
                            for (final payment in data.entries.where(
                              (e) => e.debtId == debt.id,
                            ))
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  '${payment.kind == 'repay' ? '已偿还' : '已收回'} ${money(payment.amount, currency)}',
                                ),
                                subtitle: Text(
                                  '${payment.date} · ${data.account(payment.accountId).name}',
                                ),
                                onTap: () => openForm(
                                  context,
                                  EntryForm(entry: payment),
                                ),
                              ),
                            const Divider(),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    ),
  );
}
