import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/providers.dart';
import '../../../app/widgets.dart';
import '../../../core/money/money.dart';
import '../../../core/time/business_date.dart';
import '../../../data/database/app_database.dart';
import '../domain/entry_kind.dart';
import 'accounts_page.dart';
import 'amount_pad.dart';
import 'category_icons.dart';
import '../../../core/money/calculator.dart';

class EntryForm extends ConsumerStatefulWidget {
  const EntryForm({super.key, this.entry, this.initialDate});
  final Entry? entry;
  final DateTime? initialDate;
  @override
  ConsumerState<EntryForm> createState() => _EntryFormState();
}

class _EntryFormState extends ConsumerState<EntryForm> {
  late EntryKind kind = EntryKind.values.byName(
    widget.entry?.kind ?? 'expense',
  );
  late String? accountId = widget.entry?.accountId;
  late String? targetId = widget.entry?.targetAccountId;
  late String? categoryId = widget.entry?.categoryId;
  late String? debtId = widget.entry?.debtId;
  late DateTime date = widget.entry == null
      ? widget.initialDate ?? DateTime.now()
      : parseDate(widget.entry!.date);
  final amount = TextEditingController();
  late final note = TextEditingController(text: widget.entry?.note);
  bool initialized = false, saving = false;
  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DataView(
    builder: (data) {
      if (data.accounts.isEmpty) {
        return Scaffold(
          appBar: AppBar(title: const Text('记一笔')),
          body: Center(
            child: FilledButton(
              onPressed: () => openForm(context, const AccountForm()),
              child: const Text('先添加账户'),
            ),
          ),
        );
      }
      accountId ??= data.accounts.first.id;
      final account = data.account(accountId!);
      if (!initialized) {
        if (widget.entry != null) {
          amount.text = decimalMoney(widget.entry!.amount, account.currency);
        }
        initialized = true;
      }
      final categories = data.categories
          .where((c) => c.kind == kind.name)
          .toList();
      if (!categories.any((c) => c.id == categoryId)) {
        categoryId = categories.firstOrNull?.id;
      }
      final targets = data.accounts
          .where((a) => a.id != accountId && a.currency == account.currency)
          .toList();
      if (!targets.any((a) => a.id == targetId)) {
        targetId = targets.firstOrNull?.id;
      }
      final debts = data.entries
          .where(
            (e) =>
                e.id != widget.entry?.id &&
                e.kind == (kind == EntryKind.repay ? 'borrow' : 'lend') &&
                data.account(e.accountId).currency == account.currency,
          )
          .toList();
      if (!debts.any((e) => e.id == debtId)) debtId = debts.firstOrNull?.id;
      return FormFrame(
        title: widget.entry == null ? '记一笔' : '编辑账目',
        saving: saving,
        onSave: () async {
          setState(() => saving = true);
          final ok = await perform(context, () async {
            await ref
                .read(ledgerProvider)
                .saveEntry(
                  id: widget.entry?.id,
                  kind: kind,
                  amount: calculateMinor(amount.text, account.currency),
                  accountId: accountId!,
                  targetAccountId: targetId,
                  categoryId: categoryId,
                  debtId: debtId,
                  date: dateKey(date),
                  note: note.text,
                );
          });
          if (mounted && context.mounted) {
            setState(() => saving = false);
            if (ok) Navigator.pop(context);
          }
        },
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final value in EntryKind.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(value.label),
                      selected: kind == value,
                      onSelected: (_) => setState(() => kind = value),
                    ),
                  ),
              ],
            ),
          ),

          DropdownButtonFormField<String>(
            initialValue: accountId,
            decoration: const InputDecoration(labelText: '账户'),
            items: data.accounts
                .map(
                  (a) => DropdownMenuItem(
                    value: a.id,
                    child: Text('${a.name} · ${a.currency}'),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => accountId = v),
          ),
          if (kind.needsCategory)
            LayoutBuilder(
              builder: (context, constraints) {
                final width =
                    constraints.maxWidth / (constraints.maxWidth > 400 ? 6 : 4);
                return Wrap(
                  children: [
                    for (final c in categories)
                      SizedBox(
                        width: width,
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: InkWell(
                            onTap: () => setState(() => categoryId = c.id),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 2,
                              ),
                              decoration: BoxDecoration(
                                color: categoryId == c.id
                                    ? Theme.of(context)
                                          .colorScheme
                                          .primaryContainer
                                    : null,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  Icon(categoryIcon(c.name)),
                                  const SizedBox(height: 4),
                                  Text(
                                    c.name,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('日期'),
            subtitle: Text(dateKey(date)),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final value = await showDatePicker(
                context: context,
                initialDate: date,
                firstDate: DateTime(1900),
                lastDate: DateTime(2100),
              );
              if (value != null) setState(() => date = value);
            },
          ),
          if (kind == EntryKind.transfer)
            DropdownButtonFormField<String>(
              key: ValueKey('target-$accountId'),
              initialValue: targetId,
              decoration: const InputDecoration(labelText: '转入账户 · 同币种'),
              items: targets
                  .map(
                    (a) => DropdownMenuItem(value: a.id, child: Text(a.name)),
                  )
                  .toList(),
              onChanged: (v) => targetId = v,
            ),
          if (kind.isSettlement)
            DropdownButtonFormField<String>(
              key: ValueKey('debt-${kind.name}-$accountId'),
              isExpanded: true,
              initialValue: debtId,
              decoration: const InputDecoration(labelText: '原始借贷'),
              items: debts
                  .map(
                    (e) => DropdownMenuItem(
                      value: e.id,
                      child: Text(
                        '${e.date} ${e.note.isEmpty ? data.account(e.accountId).name : e.note} ${money(e.amount, account.currency)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => debtId = v,
            ),
          TextField(
            controller: note,
            maxLength: 2000,
            maxLines: 3,
            decoration: const InputDecoration(labelText: '备注 / 往来人'),
          ),
          if (kind == EntryKind.borrow || kind == EntryKind.lend)
            const Text('借贷本金不计入收入或支出，后续通过“偿还借入 / 收回借出”结算。'),
          if (kind == EntryKind.transfer && targets.isEmpty)
            const Text('需要再添加一个同币种账户才能转账。'),
          if (kind.isSettlement && debts.isEmpty)
            const Text('暂无对应币种的原始借贷，请先记录借入或借出。'),
          AmountPad(controller: amount, currency: account.currency),
        ],
      );
    },
  );
}
