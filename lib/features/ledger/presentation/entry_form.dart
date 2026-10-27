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
import 'purchase_item_dialog.dart';
import '../domain/entry_draft.dart';

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
  late final draft = EntryDraft(
    kind: EntryKind.values.byName(
      widget.entry?.kind ?? widget.initialKind?.name ?? 'expense',
    ),
    accountId:
        widget.entry?.accountId ??
        widget.initialDebt?.accountId ??
        widget.initialAccountId,
    targetId: widget.entry?.targetAccountId,
    categoryId: widget.entry?.categoryId,
    debtId: widget.entry?.debtId ?? widget.initialDebt?.id,
    debtAccountId:
        widget.entry?.debtAccountId ??
        widget.initialDebt?.debtAccountId ??
        widget.initialDebtAccountId,
    date: widget.entry == null
        ? widget.initialDate ?? DateTime.now()
        : parseDate(widget.entry!.date),
  );
  EntryKind get kind => draft.kind;
  String? get accountId => draft.accountId;
  set accountId(String? value) => draft.accountId = value;
  String? get targetId => draft.targetId;
  set targetId(String? value) => draft.targetId = value;
  String? get categoryId => draft.categoryId;
  set categoryId(String? value) => draft.categoryId = value;
  String? get debtId => draft.debtId;
  set debtId(String? value) => draft.debtId = value;
  String? get debtAccountId => draft.debtAccountId;
  set debtAccountId(String? value) => draft.debtAccountId = value;
  DateTime get date => draft.date;
  set date(DateTime value) => draft.date = value;
  NewPurchaseItem? get item => draft.item;
  set item(NewPurchaseItem? value) => draft.item = value;
  final amount = TextEditingController();
  bool promptedItem = false;
  late final note = TextEditingController(text: widget.entry?.note);
  late final counterparty = TextEditingController(
    text: widget.entry?.counterparty ?? widget.initialCounterparty,
  );
  bool initialized = false, saving = false;
  @override
  void dispose() {
    amount.dispose();
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
      if (widget.initialRecordItem &&
          !promptedItem &&
          kind == EntryKind.expense) {
        promptedItem = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) editItem(data, account.currency);
        });
      }
      final isDebt = !kind.needsCategory && kind != EntryKind.transfer;
      final selectedDebt = debts.where((e) => e.id == debtId).firstOrNull;
      final debtAccount = debtAccounts
          .where((a) => a.id == debtAccountId)
          .firstOrNull;
      final colors = Theme.of(context).colorScheme;
      Widget fundsParty(String role) => party(
        role,
        account.name,
        () => pickAccount('选择收支账户', funds, accountId, (value) {
          if (data.account(value).currency != account.currency) item = null;
          accountId = value;
        }),
        key: const ValueKey('entry-account'),
      );
      Widget debtParty(String role) => party(
        role,
        kind.isSettlement
            ? selectedDebt == null
                  ? '选择原始借贷'
                  : '${selectedDebt.counterparty} · 剩余 ${decimalMoney(debtRemaining(selectedDebt, data.entries, excludingId: widget.entry?.id), account.currency)}'
            : debtAccount?.name ?? '选择$debtSide账户',
        () async {
          if (!kind.isSettlement) {
            await pickAccount(
              '选择$debtSide账户',
              debtAccounts,
              debtAccountId,
              (value) => debtAccountId = value,
            );
          } else {
            final value = await showModalBottomSheet<String>(
              context: context,
              isScrollControlled: true,
              builder: (context) => SafeArea(
                child: SizedBox(
                  height: MediaQuery.sizeOf(context).height * .65,
                  child: Column(
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('选择原始借贷'),
                      ),
                      Expanded(
                        child: ListView(
                          children: [
                            if (debts.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(20),
                                child: Text('暂无可结算借贷，请先记录借入或借出。'),
                              ),
                            for (final e in debts)
                              ListTile(
                                title: Text(
                                  e.counterparty.isEmpty
                                      ? '未注明往来人'
                                      : e.counterparty,
                                ),
                                subtitle: Text(
                                  '${e.date} · 剩余 ${money(debtRemaining(e, data.entries, excludingId: widget.entry?.id), account.currency)}${e.note.isEmpty ? '' : ' · ${e.note}'}',
                                ),
                                selected: e.id == debtId,
                                onTap: () => Navigator.pop(context, e.id),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
            if (mounted && value != null) setState(() => debtId = value);
          }
        },
        key: const ValueKey('entry-debt'),
      );
      return PopScope(
        canPop: !saving,
        child: Scaffold(
          appBar: AppBar(
            leadingWidth: 36,
            titleSpacing: 0,
            title: Row(
              children: [
                for (final tab in ['支出', '收入', '转账', '债务'])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Semantics(
                        selected: tab == (isDebt ? '债务' : kind.label),
                        child: InkWell(
                          key: ValueKey('entry-tab-$tab'),
                          borderRadius: BorderRadius.circular(10),
                          onTap: saving
                              ? null
                              : () => changeKind(switch (tab) {
                                  '支出' => EntryKind.expense,
                                  '收入' => EntryKind.income,
                                  '转账' => EntryKind.transfer,
                                  _ => isDebt ? kind : EntryKind.borrow,
                                }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: tab == (isDebt ? '债务' : kind.label)
                                  ? colors.primaryContainer
                                  : colors.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              tab,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Center(
                  child: Text(
                    account.currency,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ),
            ],
          ),
          body: SafeArea(
            bottom: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Card(
                  margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                  child: ListView(
                    key: const ValueKey('entry-content'),
                    padding: const EdgeInsets.all(10),
                    children: [
                      if (kind.needsCategory)
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final scaled = MediaQuery.textScalerOf(context)
                                .scale(14);
                            final columns = scaled > 18
                                ? 3
                                : constraints.maxWidth < 340
                                ? 4
                                : 5;
                            return Wrap(
                              children: [
                                for (final c in categories)
                                  SizedBox(
                                    width: constraints.maxWidth / columns,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                        horizontal: 2,
                                      ),
                                      child: Semantics(
                                        button: true,
                                        selected: categoryId == c.id,
                                        child: InkWell(
                                          key: ValueKey(
                                            'entry-category-${c.id}',
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          onTap: saving
                                              ? null
                                              : () => setState(
                                                  () => categoryId = c.id,
                                                ),
                                          child: Column(
                                            children: [
                                              Container(
                                                width: 44,
                                                height: 44,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: categoryId == c.id
                                                      ? colors.primaryContainer
                                                      : colors
                                                            .surfaceContainerLow,
                                                ),
                                                child: Icon(
                                                  categoryIcon(c.name),
                                                  color: categoryId == c.id
                                                      ? colors
                                                            .onPrimaryContainer
                                                      : colors.onSurface,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                c.name,
                                                textAlign: TextAlign.center,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelMedium
                                                    ?.copyWith(
                                                      color: categoryId == c.id
                                                          ? colors.primary
                                                          : null,
                                                    ),
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
                      if (isDebt) ...[
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('新增借贷'),
                              selected: !kind.isSettlement,
                              onSelected: saving
                                  ? null
                                  : (_) => changeKind(
                                      kind == EntryKind.collect
                                          ? EntryKind.lend
                                          : EntryKind.borrow,
                                    ),
                            ),
                            ChoiceChip(
                              label: const Text('偿还 / 收回'),
                              selected: kind.isSettlement,
                              onSelected: saving
                                  ? null
                                  : (_) => changeKind(
                                      kind == EntryKind.lend
                                          ? EntryKind.collect
                                          : EntryKind.repay,
                                    ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            kind.label,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                      if (!kind.needsCategory) ...[
                        if (kind == EntryKind.transfer || kind.direction < 0)
                          fundsParty('付款方')
                        else
                          debtParty('付款方'),
                        Center(
                          child: IconButton(
                            key: const ValueKey('entry-swap'),
                            tooltip: '交换付款方与收款方',
                            onPressed: saving
                                ? null
                                : () => setState(draft.exchangeParties),
                            icon: const Icon(Icons.swap_vert),
                          ),
                        ),
                        if (kind == EntryKind.transfer)
                          party(
                            '收款方',
                            targets
                                    .where((a) => a.id == targetId)
                                    .firstOrNull
                                    ?.name ??
                                '选择同币种账户',
                            () => pickAccount(
                              '选择同币种转入账户',
                              targets,
                              targetId,
                              (value) => targetId = value,
                            ),
                            key: const ValueKey('entry-target'),
                          )
                        else if (kind.direction < 0)
                          debtParty('收款方')
                        else
                          fundsParty('收款方'),
                        if (isDebt && !kind.isSettlement)
                          TextButton.icon(
                            icon: const Icon(Icons.person_add_outlined),
                            label: Text('创建$debtSide账户'),
                            onPressed: saving
                                ? null
                                : () async {
                                    final id = await Navigator.of(context)
                                        .push<String>(
                                          MaterialPageRoute(
                                            builder: (_) => AccountForm(
                                              initialKind: '债务',
                                              initialChannel: debtSide,
                                              initialName:
                                                  widget.initialCounterparty,
                                              initialCurrency: account.currency,
                                            ),
                                          ),
                                        );
                                    if (mounted && id != null) {
                                      setState(() => debtAccountId = id);
                                    }
                                  },
                          ),
                        const SizedBox(height: 12),
                        Text(
                          kind == EntryKind.transfer
                              ? '转账只在两个同币种账户之间移动资金，不计入收支。'
                              : kind.isSettlement
                              ? '选择原始借贷后结算，金额不能超过剩余本金。'
                              : '借贷本金不计入收入或支出，后续在“偿还 / 收回”中结算。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          bottomNavigationBar: KeyboardActionBar(
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                  child: AmountPad(
                    controller: amount,
                    currency: account.currency,
                    saving: saving,
                    onSave: () => save(data, account.currency),
                    onSaveAnother: widget.entry == null
                        ? () => save(data, account.currency, another: true)
                        : null,
                    leading: TextButton(
                      key: const ValueKey('entry-note'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                      onPressed: saving ? null : editNote,
                      child: Text(
                        note.text.isEmpty ? '添加备注' : note.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    toolbar: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          TextButton.icon(
                            key: const ValueKey('entry-date'),
                            icon: const Icon(
                              Icons.calendar_today_outlined,
                              size: 18,
                            ),
                            label: Text(
                              '日期 ${dateKey(date) == dateKey(DateTime.now()) ? '今天' : dateKey(date)}',
                            ),
                            onPressed: saving
                                ? null
                                : () async {
                                    final value = await showDatePicker(
                                      context: context,
                                      initialDate: date,
                                      firstDate: DateTime(1900),
                                      lastDate: DateTime(2100),
                                    );
                                    if (mounted && value != null) {
                                      setState(() => date = value);
                                    }
                                  },
                          ),
                          TextButton.icon(
                            key: const ValueKey('entry-account-shortcut'),
                            icon: const Icon(
                              Icons.account_balance_wallet_outlined,
                              size: 18,
                            ),
                            label: Text(account.name),
                            onPressed: saving
                                ? null
                                : () => pickAccount(
                                    '选择收支账户',
                                    funds,
                                    accountId,
                                    (value) {
                                      if (data.account(value).currency !=
                                          account.currency) {
                                        item = null;
                                      }
                                      accountId = value;
                                    },
                                  ),
                          ),
                          if (kind == EntryKind.expense)
                            TextButton.icon(
                              key: const ValueKey('entry-item'),
                              icon: Icon(
                                item == null
                                    ? Icons.inventory_2_outlined
                                    : Icons.check_circle_outline,
                                size: 18,
                              ),
                              label: Text(
                                item == null ? '记物' : '记物 · ${item!.name}',
                              ),
                              onPressed: saving
                                  ? null
                                  : () => editItem(data, account.currency),
                            ),
                          if (kind == EntryKind.expense && item != null)
                            IconButton(
                              tooltip: '取消记物',
                              onPressed: saving
                                  ? null
                                  : () => setState(() => item = null),
                              icon: const Icon(Icons.close, size: 18),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  void changeKind(EntryKind value) {
    if (value == kind) return;
    setState(() => draft.changeKind(value));
  }

  Widget party(String role, String value, VoidCallback action, {Key? key}) =>
      Card(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: ListTile(
          key: key,
          leading: const Icon(Icons.account_balance_wallet_outlined),
          title: Text(role),
          subtitle: Text(value),
          trailing: const Icon(Icons.chevron_right),
          onTap: saving ? null : action,
        ),
      );

  Future<void> pickAccount(
    String title,
    List<Account> accounts,
    String? selected,
    ValueChanged<String> onSelected,
  ) async {
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    if (accounts.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('暂无可选账户，请先创建对应币种和类型的账户。'),
                      ),
                    for (final group in accountKinds)
                      if (accounts.any((a) => a.kind == group)) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text(group),
                        ),
                        for (final account in accounts.where(
                          (a) => a.kind == group,
                        ))
                          ListTile(
                            title: Text(account.name),
                            subtitle: Text(
                              '${account.channel} · ${account.currency}',
                            ),
                            selected: account.id == selected,
                            trailing: account.id == selected
                                ? const Icon(Icons.check)
                                : null,
                            onTap: () => Navigator.pop(context, account.id),
                          ),
                      ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted && value != null) setState(() => onSelected(value));
  }

  Future<void> editNote() async {
    final draft = TextEditingController(text: note.text);
    final route = DialogRoute<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('备注'),
        scrollable: true,
        content: TextField(
          controller: draft,
          minLines: 2,
          maxLines: 5,
          maxLength: 2000,
          decoration: const InputDecoration(labelText: '备注'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, draft.text),
            child: const Text('确认备注'),
          ),
        ],
      ),
    );
    final result = await Navigator.of(context).push(route);
    if (mounted && result != null) setState(() => note.text = result);
    await route.completed;
    draft.dispose();
  }

  Future<void> editItem(AppSnapshot data, String currency) async {
    final result = await showDialog<NewPurchaseItem>(
      context: context,
      builder: (_) => PurchaseItemDialog(
        currency: currency,
        initial: item,
        categories: {
          ...configuredItemCategories(
            data.preferences
                .where((p) => p.key == 'item_categories')
                .firstOrNull
                ?.value,
          ),
          ...data.items.expand((i) => itemTags(i.category)),
        }.toList(),
      ),
    );
    if (mounted && result != null) setState(() => item = result);
  }

  Future<void> save(
    AppSnapshot data,
    String currency, {
    bool another = false,
  }) async {
    if (saving) return;
    setState(() => saving = true);
    final ok = await perform(context, () async {
      await draft.save(
        ref.read(ledgerProvider),
        id: widget.entry?.id,
        currency: currency,
        amount: amount.text,
        note: note.text,
        counterparty: counterparty.text,
      );
    });
    if (!mounted) return;
    setState(() => saving = false);
    if (ok) {
      if (another) {
        setState(() {
          amount.clear();
          note.clear();
          draft.prepareAnother();
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已保存，继续记一笔')));
      } else {
        Navigator.pop(context);
      }
    }
  }
}
