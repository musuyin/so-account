import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/providers.dart';
import '../../../app/widgets.dart';
import '../../../core/money/money.dart';
import '../../../core/time/business_date.dart';
import '../../../data/database/app_database.dart';
import '../../inventory/domain/item_categories.dart';
import '../../inventory/domain/new_purchase_item.dart';
import '../domain/entry_kind.dart';
import '../domain/debt_relationship.dart';
import 'accounts_page.dart';
import 'amount_pad.dart';
import 'category_icons.dart';
import '../../../core/money/calculator.dart';

class EntryForm extends ConsumerStatefulWidget {
  const EntryForm({
    super.key,
    this.entry,
    this.initialDate,
    this.initialKind,
    this.initialDebt,
    this.initialCounterparty,
    this.initialDebtAccountId,
    this.initialAccountId,
    this.initialCurrency,
    this.initialRecordItem = false,
  });
  final Entry? entry;
  final EntryKind? initialKind;
  final Entry? initialDebt;
  final String? initialCounterparty;
  final String? initialDebtAccountId;
  final String? initialAccountId;
  final String? initialCurrency;
  final bool initialRecordItem;
  final DateTime? initialDate;
  @override
  ConsumerState<EntryForm> createState() => _EntryFormState();
}

class _EntryFormState extends ConsumerState<EntryForm> {
  late EntryKind kind = EntryKind.values.byName(
    widget.entry?.kind ?? widget.initialKind?.name ?? 'expense',
  );
  late String? accountId =
      widget.entry?.accountId ??
      widget.initialDebt?.accountId ??
      widget.initialAccountId;
  late String? targetId = widget.entry?.targetAccountId;
  late String? categoryId = widget.entry?.categoryId;
  late String? debtId = widget.entry?.debtId ?? widget.initialDebt?.id;
  late String? debtAccountId =
      widget.entry?.debtAccountId ??
      widget.initialDebt?.debtAccountId ??
      widget.initialDebtAccountId;
  late DateTime date = widget.entry == null
      ? widget.initialDate ?? DateTime.now()
      : parseDate(widget.entry!.date);
  final amount = TextEditingController();
  final itemName = TextEditingController();
  final itemPrice = TextEditingController();
  final itemQuantity = TextEditingController();
  final itemUnit = TextEditingController();
  late bool recordItem = widget.initialRecordItem;
  String? itemCategory;
  String itemUseType = 'durable';
  late final note = TextEditingController(text: widget.entry?.note);
  late final counterparty = TextEditingController(
    text: widget.entry?.counterparty ?? widget.initialCounterparty,
  );
  bool initialized = false, saving = false;
  @override
  void dispose() {
    amount.dispose();
    itemName.dispose();
    itemPrice.dispose();
    itemQuantity.dispose();
    itemUnit.dispose();
    note.dispose();
    counterparty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DataView(
    builder: (data) {
      final historical = widget.entry ?? widget.initialDebt;
      if (historical != null && data.hasArchivedAccount(historical)) {
        return Scaffold(
          appBar: AppBar(title: const Text('历史账目')),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text('关联账户已归档，历史记录只读。如需修改或结算，请先在设置 → 归档账户中恢复。'),
              const SizedBox(height: 16),
              Text(
                '${EntryKind.values.byName(historical.kind).label} · ${money(historical.amount, data.account(historical.accountId).currency)}',
              ),
              Text(historical.date),
              Text('账户：${data.account(historical.accountId).name}'),
              if (historical.targetAccountId != null)
                Text('转入：${data.account(historical.targetAccountId!).name}'),
              if (historical.debtAccountId != null)
                Text('债务账户：${data.account(historical.debtAccountId!).name}'),
              Text(data.category(historical.categoryId)),
              if (historical.note.isNotEmpty) Text(historical.note),
            ],
          ),
        );
      }
      final archivedSelection = data.accounts.any(
        (a) =>
            a.isArchived &&
            [
              accountId,
              if (kind == EntryKind.transfer) targetId,
              if (kind == EntryKind.borrow || kind == EntryKind.lend)
                debtAccountId,
            ].contains(a.id),
      );
      if (archivedSelection) {
        return Scaffold(
          appBar: AppBar(title: const Text('记一笔')),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text('所选账户已归档。请重新选择账户，或在设置 → 归档账户中恢复。'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => setState(() {
                  accountId = targetId = debtAccountId = debtId = null;
                }),
                child: const Text('重新选择账户'),
              ),
            ],
          ),
        );
      }
      final funds = data.activeAccounts
          .where((a) => kind == EntryKind.transfer || a.kind != '债务')
          .toList();
      if (funds.isEmpty ||
          (!initialized &&
              accountId == null &&
              widget.initialCurrency != null &&
              !funds.any((a) => a.currency == widget.initialCurrency))) {
        return Scaffold(
          appBar: AppBar(title: const Text('记一笔')),
          body: Center(
            child: FilledButton(
              onPressed: () => openForm(
                context,
                AccountForm(initialCurrency: widget.initialCurrency),
              ),
              child: Text('先添加${widget.initialCurrency ?? ''}账户'),
            ),
          ),
        );
      }
      if (!funds.any((a) => a.id == accountId)) {
        accountId =
            funds
                .where((a) => a.currency == widget.initialCurrency)
                .firstOrNull
                ?.id ??
            funds.first.id;
      }
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
      final targets = data.activeAccounts
          .where((a) => a.id != accountId && a.currency == account.currency)
          .toList();
      if (!targets.any((a) => a.id == targetId)) {
        targetId = targets.firstOrNull?.id;
      }
      final debts = data.entries
          .where(
            (e) =>
                e.id != widget.entry?.id &&
                !data.hasArchivedAccount(e) &&
                e.kind == (kind == EntryKind.repay ? 'borrow' : 'lend') &&
                (debtRemaining(e, data.entries, excludingId: widget.entry?.id) >
                        0 ||
                    e.id == debtId) &&
                data.account(e.accountId).currency == account.currency,
          )
          .toList();
      if (!debts.any((e) => e.id == debtId)) debtId = null;
      final debtSide = kind == EntryKind.borrow ? '应付款' : '应收款';
      final debtAccounts = data.activeAccounts
          .where(
            (a) =>
                a.kind == '债务' &&
                a.currency == account.currency &&
                (a.channel == debtSide ||
                    (debtSide == '应收款' && a.channel == '报销')),
          )
          .toList();
      if (!debtAccounts.any((a) => a.id == debtAccountId)) debtAccountId = null;
      return FormFrame(
        title: widget.entry == null ? '记一笔' : '编辑账目',
        saving: saving,
        currency: account.currency,
        header: SingleChildScrollView(
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
        footer: AmountPad(controller: amount, currency: account.currency),
        onSave: () async {
          if (saving) return;
          setState(() => saving = true);
          final ok = await perform(context, () async {
            if ([EntryKind.borrow, EntryKind.lend].contains(kind) &&
                debtAccountId == null) {
              throw const FormatException('请选择或创建债务账户');
            }
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
                  counterparty: kind.isSettlement ? '' : counterparty.text,
                  debtAccountId: debtAccountId,
                  date: dateKey(date),
                  note: note.text,
                  newItem: kind == EntryKind.expense && recordItem
                      ? NewPurchaseItem(
                          name: itemName.text,
                          category: itemCategory ?? '',
                          useType: itemUseType,
                          price: itemPrice.text.trim().isEmpty
                              ? null
                              : parseMoney(itemPrice.text, account.currency),
                          quantity: itemUseType == 'consumable'
                              ? itemQuantity.text
                              : null,
                          unit: itemUseType == 'consumable'
                              ? itemUnit.text
                              : null,
                        )
                      : null,
                );
          });
          if (mounted && context.mounted) {
            setState(() => saving = false);
            if (ok) Navigator.pop(context);
          }
        },
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey('account-$accountId'),
            isExpanded: true,
            initialValue: accountId,
            decoration: const InputDecoration(labelText: '账户'),
            selectedItemBuilder: (_) => [
              for (final a in funds)
                Text(a.name, overflow: TextOverflow.ellipsis),
            ],
            items: funds
                .map(
                  (a) => DropdownMenuItem(
                    value: a.id,
                    child: Text(
                      '${a.name} · ${a.currency}',
                      overflow: TextOverflow.ellipsis,
                    ),
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
          if ([EntryKind.borrow, EntryKind.lend].contains(kind)) ...[
            DropdownButtonFormField<String>(
              key: ValueKey(
                'debt-account-${kind.name}-$accountId-$debtAccountId',
              ),
              initialValue: debtAccountId,
              isExpanded: true,
              decoration: InputDecoration(labelText: '$debtSide账户'),
              items: [
                for (final a in debtAccounts)
                  DropdownMenuItem(
                    value: a.id,
                    child: Text('${a.name} · ${a.channel}'),
                  ),
              ],
              onChanged: (v) => setState(() => debtAccountId = v),
            ),
            TextButton.icon(
              icon: const Icon(Icons.person_add_outlined),
              label: Text('创建$debtSide账户'),
              onPressed: () async {
                final id = await Navigator.of(context).push<String>(
                  MaterialPageRoute(
                    builder: (_) => AccountForm(
                      initialKind: '债务',
                      initialChannel: debtSide,
                      initialName: widget.initialCounterparty,
                      initialCurrency: account.currency,
                    ),
                  ),
                );
                if (mounted && id != null) setState(() => debtAccountId = id);
              },
            ),
          ],
          if (kind.isSettlement) ...[
            DropdownButtonFormField<String>(
              key: ValueKey('debt-${kind.name}-$accountId-$debtId'),
              isExpanded: true,
              initialValue: debtId,
              decoration: const InputDecoration(labelText: '原始借贷'),
              items: debts
                  .map(
                    (e) => DropdownMenuItem(
                      value: e.id,
                      child: Text(
                        '${e.counterparty.isEmpty ? '未注明往来人' : e.counterparty} · ${e.date} · 剩余 ${money(debtRemaining(e, data.entries, excludingId: widget.entry?.id), account.currency)}${e.note.isEmpty ? '' : ' · ${e.note}'}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => debtId = v),
            ),
            if (debtId != null)
              Text(
                '往来人：${debts.firstWhere((e) => e.id == debtId).counterparty.isEmpty ? '未注明往来人' : debts.firstWhere((e) => e.id == debtId).counterparty}',
              ),
          ],
          TextField(
            controller: note,
            maxLength: 2000,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(labelText: '备注'),
          ),
          if (kind == EntryKind.borrow || kind == EntryKind.lend)
            const Text('借贷本金不计入收入或支出，后续通过“偿还借入 / 收回借出”结算。'),
          if (kind == EntryKind.transfer && targets.isEmpty)
            const Text('需要再添加一个同币种账户才能转账。'),
          if (kind.isSettlement && debts.isEmpty)
            const Text('暂无对应币种的原始借贷，请先记录借入或借出。'),
          if (kind == EntryKind.expense) ...[
            SwitchListTile.adaptive(
              key: const ValueKey('record-item-switch'),
              contentPadding: EdgeInsets.zero,
              title: const Text('同步记物'),
              subtitle: widget.entry == null ? null : const Text('新增物品并关联此笔支出'),
              value: recordItem,
              onChanged: saving
                  ? null
                  : (value) => setState(() => recordItem = value),
            ),
            if (recordItem) _buildItemFields(data, account.currency),
          ],
        ],
      );
    },
  );

  Widget _buildItemFields(AppSnapshot data, String currency) => Card(
    key: const ValueKey('inline-purchase-item'),
    borderOnForeground: false,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: itemName,
            maxLength: 100,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '物品名称',
              counterText: '',
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: const ValueKey('inline-item-category'),
            initialValue: itemCategory,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '物品类型',
              hintText: '请选择物品类型',
            ),
            items: [
              for (final category in {
                ...configuredItemCategories(
                  data.preferences
                      .where((p) => p.key == 'item_categories')
                      .firstOrNull
                      ?.value,
                ),
                ...data.items.expand((item) => itemTags(item.category)),
                ?itemCategory,
                '未分类',
              })
                DropdownMenuItem(
                  value: category,
                  child: Text(category, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) => setState(() => itemCategory = value),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: const ValueKey('inline-item-use-type'),
            initialValue: itemUseType,
            decoration: const InputDecoration(labelText: '使用属性'),
            items: const [
              DropdownMenuItem(value: 'durable', child: Text('长期使用物')),
              DropdownMenuItem(value: 'consumable', child: Text('消耗品')),
            ],
            onChanged: (value) => setState(() => itemUseType = value!),
          ),
          if (itemUseType == 'consumable') ...[
            const SizedBox(height: 10),
            TextField(
              controller: itemQuantity,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: '数量 / 容量 · 可留空'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: itemUnit,
              maxLength: 20,
              decoration: const InputDecoration(
                labelText: '单位 · 可留空',
                counterText: '',
              ),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: itemPrice,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: '物品价格（选填）',
              helperText: '单独填写这件物品的价格，不自动分配整笔支出。',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '购入日期 ${dateKey(date)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}
