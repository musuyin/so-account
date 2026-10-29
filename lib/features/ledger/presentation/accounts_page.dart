import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/providers.dart';
import '../../../app/widgets.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/money/money.dart';
import '../../../data/database/app_database.dart';
import '../domain/entry_kind.dart';
import '../domain/banks.dart';
import '../domain/asset_summary.dart';
import 'account_avatar.dart';
import 'account_type_picker.dart';
import 'people_debts_page.dart';
import 'balance_adjustment_form.dart';
import '../../goals/presentation/goals_page.dart';
import 'account_detail_page.dart';
import 'account_actions.dart';
import 'finance_page.dart';

class AccountsPage extends ConsumerStatefulWidget {
  const AccountsPage({super.key});
  @override
  ConsumerState<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends ConsumerState<AccountsPage> {
  String currency = 'CNY';
  bool get hidden => ref.watch(assetAmountsHiddenProvider);
  final collapsed = <String>{};
  List<String>? pendingOrder;
  bool ordering = false;
  String number(int value) => hidden ? '••••' : decimalMoney(value, currency);
  Widget amount(BuildContext context, int value, {TextStyle? style}) => Tooltip(
    message: hidden ? '金额已隐藏' : decimalMoney(value, currency),
    triggerMode: TooltipTriggerMode.manual,
    child: Text(
      number(value),
      style: AppTypography.amount.merge(style),
      textAlign: TextAlign.right,
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('账户'),
      actions: [
        IconButton(
          tooltip: '心愿',
          icon: const Icon(Icons.savings_outlined),
          onPressed: () =>
              openForm(context, GoalsPage(initialCurrency: currency)),
        ),
        IconButton(
          tooltip: '新增账户',
          icon: const Icon(Icons.add),
          onPressed: () =>
              openForm(context, AccountForm(initialCurrency: currency)),
        ),
        DropdownButton<String>(
          key: const ValueKey('asset-currency'),
          value: currency,
          items: [
            for (final value in currencies)
              DropdownMenuItem(value: value, child: Text(value)),
          ],
          onChanged: (value) => setState(() => currency = value!),
        ),
      ],
    ),
    body: DataView(
      builder: (data) {
        final state = ref.watch(balancesProvider);
        if (state.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.hasError) {
          return Center(
            child: TextButton(
              onPressed: () => ref.invalidate(balancesProvider),
              child: const Text('余额读取失败，点击重试'),
            ),
          );
        }
        final balances = state.value ?? {};
        final accounts = data.activeAccounts
            .where((a) => a.currency == currency)
            .toList();
        List<String> order;
        try {
          order =
              pendingOrder ??
              (jsonDecode(data.preference('account_order', '[]')) as List)
                  .cast<String>();
        } catch (_) {
          order = [];
        }
        final ranks = {for (var i = 0; i < order.length; i++) order[i]: i};
        final original = {
          for (var i = 0; i < accounts.length; i++) accounts[i].id: i,
        };
        accounts.sort(
          (a, b) => (ranks[a.id] ?? order.length + original[a.id]!).compareTo(
            ranks[b.id] ?? order.length + original[b.id]!,
          ),
        );
        Future<void> reorder(String kind, int from, int to) async {
          if (ordering) return;
          final group = accounts
              .where((a) => a.kind == kind)
              .map((a) => a.id)
              .toList();
          group.insert(to, group.removeAt(from));
          var index = 0;
          final ids = [
            ...order.where((id) => !accounts.any((a) => a.id == id)),
            for (final a in accounts) a.kind == kind ? group[index++] : a.id,
          ];
          setState(() {
            pendingOrder = ids;
            ordering = true;
          });
          await perform(context, () async {
            final db = ref.read(databaseProvider);
            await db
                .into(db.preferences)
                .insertOnConflictUpdate(
                  PreferencesCompanion.insert(
                    key: 'account_order',
                    value: jsonEncode(ids),
                  ),
                );
          });
          if (mounted) {
            setState(() {
              pendingOrder = null;
              ordering = false;
            });
          }
        }

        int balance(Account a) => balances[a.id] ?? a.openingBalance;
        int sum(Iterable<Account> rows) =>
            rows.fold(0, (value, a) => value + balance(a));
        final totals = AssetSummary.calculate(
          accounts.map((a) => assetBalance(a.channel, balance(a))),
        );
        final receivable = sum(
          accounts.where((a) => a.kind == '债务' && a.channel == '应收款'),
        );
        final payable = sum(
          accounts.where((a) => a.kind == '债务' && a.channel == '应付款'),
        );
        final reimbursement = sum(
          accounts.where((a) => a.kind == '债务' && a.channel == '报销'),
        );
        final investment = sum(accounts.where((a) => a.kind == '投资理财'));
        final colors = Theme.of(context).colorScheme;
        Widget mini(
          String title,
          List<(String, int)> values,
          IconData icon, {
          VoidCallback? onTap,
        }) => Expanded(
          child: Card(
            borderOnForeground: false,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, size: 17, color: colors.primary),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            title,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    for (final value in values)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              value.$1,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                            amount(
                              context,
                              value.$2,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
          children: [
            Card(
              key: const ValueKey('asset-overview'),
              borderOnForeground: false,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '资产总览',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: hidden ? '显示金额' : '隐藏金额',
                          onPressed: () {
                            Tooltip.dismissAllToolTips();
                            ref
                                .read(assetAmountsHiddenProvider.notifier)
                                .toggle();
                          },
                          icon: Icon(
                            hidden
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final large =
                            constraints.maxWidth < 520 ||
                            MediaQuery.textScalerOf(context).scale(14) > 18;
                        final net = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '净资产',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                            const SizedBox(height: 3),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: amount(
                                context,
                                totals.net,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                      fontSize: 21,
                                      fontWeight: FontWeight.w700,
                                      color: totals.net < 0
                                          ? colors.error
                                          : colors.primary,
                                    ),
                              ),
                            ),
                          ],
                        );
                        final details = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text('总资产'),
                                const SizedBox(width: 10),
                                Expanded(child: amount(context, totals.assets)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Text('总负债'),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: amount(context, totals.liabilities),
                                ),
                              ],
                            ),
                          ],
                        );
                        return large
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  net,
                                  const SizedBox(height: 12),
                                  details,
                                ],
                              )
                            : Row(
                                children: [
                                  Expanded(flex: 5, child: net),
                                  const SizedBox(width: 18),
                                  Expanded(flex: 4, child: details),
                                ],
                              );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  mini(
                    '报销',
                    [('待收', reimbursement)],
                    Icons.receipt_outlined,
                    onTap: () => openForm(
                      context,
                      FinancePage(investment: false, currency: currency),
                    ),
                  ),
                  const SizedBox(width: 6),
                  mini(
                    '债务',
                    [('待收', receivable), ('待还', payable)],
                    Icons.people_outline,
                    onTap: () => openForm(context, const PeopleDebtsPage()),
                  ),
                  const SizedBox(width: 6),
                  mini(
                    '理财',
                    [('成本', investment)],
                    Icons.trending_up,
                    onTap: () => openForm(
                      context,
                      FinancePage(investment: true, currency: currency),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            if (accounts.isEmpty) const EmptyState('暂无账户', '添加账户后开始记账。'),
            for (final kind in accountKinds)
              if (accounts.any((a) => a.kind == kind))
                Card(
                  borderOnForeground: false,
                  child: Column(
                    children: [
                      InkWell(
                        key: ValueKey('account-group-$kind'),
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => setState(() {
                          if (!collapsed.add(kind)) collapsed.remove(kind);
                        }),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  kind,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                              Flexible(
                                fit: FlexFit.tight,
                                child: amount(
                                  context,
                                  accounts
                                      .where((a) => a.kind == kind)
                                      .fold<int>(
                                        0,
                                        (sum, a) =>
                                            sum +
                                            assetBalance(a.channel, balance(a)),
                                      ),
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(color: colors.primary),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                collapsed.contains(kind)
                                    ? Icons.expand_more
                                    : Icons.expand_less,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (!collapsed.contains(kind)) ...[
                        const Divider(height: 1),
                        ReorderableListView(
                          shrinkWrap: true,
                          buildDefaultDragHandles: false,
                          physics: const NeverScrollableScrollPhysics(),
                          onReorderItem: (from, to) => reorder(kind, from, to),
                          children: [
                            for (final account in accounts.where(
                              (a) => a.kind == kind,
                            ))
                              ReorderableDelayedDragStartListener(
                                key: ValueKey('asset-account-${account.id}'),
                                index: accounts
                                    .where((a) => a.kind == kind)
                                    .toList()
                                    .indexOf(account),
                                child: ListTile(
                                  leading: AccountAvatar(
                                    account: account,
                                    radius: 17,
                                  ),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          account.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        fit: FlexFit.tight,
                                        child: amount(
                                          context,
                                          balance(account),
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                color:
                                                    assetBalance(
                                                          account.channel,
                                                          balance(account),
                                                        ) <
                                                        0
                                                    ? colors.error
                                                    : assetBalance(
                                                            account.channel,
                                                            balance(account),
                                                          ) >
                                                          0
                                                    ? colors.primary
                                                    : colors.onSurfaceVariant,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      ParameterRow([
                                        if (account.bank.isNotEmpty)
                                          bankLabels[account.bank] ?? '其他银行',
                                        account.channel == '自定义' &&
                                                account.customChannel.isNotEmpty
                                            ? account.customChannel
                                            : account.channel,
                                        if (account.kind == '投资理财') '按买入成本',
                                      ]),
                                      if (account.creditLimit != null)
                                        ParameterRow([
                                          '额度',
                                          hidden
                                              ? '••••'
                                              : decimalMoney(
                                                  account.creditLimit!,
                                                  currency,
                                                ),
                                        ]),
                                      if (account.creditLimit != null)
                                        ParameterRow([
                                          '可用',
                                          hidden
                                              ? '••••'
                                              : decimalMoney(
                                                  account.creditLimit! +
                                                      (balance(account) < 0
                                                          ? balance(account)
                                                          : 0),
                                                  currency,
                                                ),
                                        ]),
                                    ],
                                  ),
                                  onTap: () => openForm(
                                    context,
                                    AccountDetailPage(id: account.id),
                                  ),
                                  trailing: AccountActionsButton(
                                    account: account,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
          ],
        );
      },
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () =>
          openForm(context, AccountForm(initialCurrency: currency)),
      icon: const Icon(Icons.add),
      label: const Text('添加账户'),
    ),
  );
}

class AccountForm extends ConsumerStatefulWidget {
  const AccountForm({
    super.key,
    this.account,
    this.initialName,
    this.importContext,
    this.initialKind,
    this.initialChannel,
    this.initialCurrency,
  });
  final Account? account;
  final String? initialName;
  final String? importContext;
  final String? initialKind, initialChannel;
  final String? initialCurrency;
  @override
  ConsumerState<AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends ConsumerState<AccountForm> {
  late final name = TextEditingController(
    text: widget.account?.name ?? widget.initialName,
  );
  late String? currency =
      widget.account?.currency ??
      widget.initialCurrency ??
      (widget.importContext == null ? 'CNY' : null);
  late String? kind =
      widget.account?.kind ??
      widget.initialKind ??
      (widget.importContext == null ? accountKinds.first : null);
  late String? channel =
      widget.account?.channel ??
      widget.initialChannel ??
      (widget.importContext == null ? accountTypes[kind]!.first : null);
  late final custom = TextEditingController(
    text: widget.account?.customChannel,
  );
  late final creditLimit = TextEditingController(
    text: widget.account?.creditLimit == null
        ? ''
        : decimalMoney(widget.account!.creditLimit!, currency ?? 'CNY'),
  );
  late final unitPrice = TextEditingController(text: widget.account?.unitPrice);
  late final opening = TextEditingController(
    text: widget.importContext == null
        ? decimalMoney(widget.account?.openingBalance ?? 0, currency ?? 'CNY')
        : '',
  );
  late String avatar = widget.account?.avatar ?? '';
  late String bank = widget.account?.bank ?? '';
  bool saving = false;
  late bool showTypeChoices =
      widget.account == null && widget.initialChannel == null;
  bool get balanceLocked {
    final id = widget.account?.id;
    final data = ref.watch(snapshotProvider).value;
    return id != null &&
        ((data?.entries.any(
                  (e) =>
                      e.accountId == id ||
                      e.targetAccountId == id ||
                      e.debtAccountId == id,
                ) ??
                false) ||
            (data?.adjustments.any((a) => a.accountId == id) ?? false));
  }

  void selectType(String value, String selectedChannel) => setState(() {
    final previousChannel = channel;
    kind = value;
    channel = selectedChannel;
    if (!isBankChannel(channel)) bank = '';
    if (widget.account == null) {
      avatar = switch (channel) {
        '微信' => 'wechat',
        '支付宝' => 'alipay',
        '银行卡' || '信用卡' => 'bank',
        '花呗' => 'huabei',
        _ => '',
      };
      if (widget.initialName == null &&
          (name.text.isEmpty || name.text == previousChannel)) {
        name.text = selectedChannel == '自定义' ? '' : selectedChannel;
      }
    }
    showTypeChoices = false;
  });

  @override
  void dispose() {
    name.dispose();
    opening.dispose();
    custom.dispose();
    unitPrice.dispose();
    creditLimit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormFrame(
    title: widget.account == null ? '添加账户' : '编辑账户',
    saving: saving,
    onSave: () async {
      setState(() => saving = true);
      String? savedId;
      final ok = await perform(context, () async {
        if (kind == null || channel == null || currency == null) {
          throw const FormatException('请选择账户类型、渠道和币种');
        }
        if (channel == '自定义' && custom.text.trim().isEmpty) {
          throw const FormatException('请填写自定义类别');
        }
        savedId = await ref
            .read(ledgerProvider)
            .saveAccount(
              id: widget.account?.id,
              name: name.text,
              kind: kind!,
              channel: channel!,
              currency: currency!,
              openingBalance: parseMoney(opening.text, currency!, signed: true),
              avatar: avatar,
              bank: bank,
              customChannel: custom.text,
              unitPrice: unitPrice.text,
              creditLimit: kind == '信贷账户' && creditLimit.text.trim().isNotEmpty
                  ? parseMoney(creditLimit.text, currency!)
                  : null,
            );
      });
      if (mounted && context.mounted) {
        setState(() => saving = false);
        if (ok) Navigator.pop(context, savedId);
      }
    },
    children: [
      DropdownButtonFormField<String>(
        key: ValueKey('account-currency-$currency'),
        initialValue: currency,
        decoration: const InputDecoration(labelText: '币种'),
        items: [
          for (final value in currencies)
            DropdownMenuItem(value: value, child: Text(value)),
        ],
        onChanged: balanceLocked
            ? null
            : (value) => setState(() {
                if (opening.text == '0' || opening.text == '0.00') {
                  opening.text = decimalMoney(0, value!);
                }
                currency = value!;
              }),
      ),
      if (widget.importContext != null)
        Card(
          borderOnForeground: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '${widget.importContext}\n请填写本批最早交易之前的余额，而非当前余额。保存后账户即创建，取消导入会保留该账户。',
            ),
          ),
        ),
      TextField(
        controller: name,
        maxLength: 80,
        decoration: const InputDecoration(labelText: '账户名称'),
      ),
      if (widget.account != null)
        TextButton.icon(
          icon: const Icon(Icons.tune),
          label: const Text('余额调整'),
          onPressed:
              ref.watch(balancesProvider).value?[widget.account!.id] == null
              ? null
              : () => openForm(
                  context,
                  BalanceAdjustmentForm(
                    account: widget.account!,
                    balance: ref
                        .read(balancesProvider)
                        .value![widget.account!.id]!,
                  ),
                ),
        ),
      if (!showTypeChoices)
        Card(
          borderOnForeground: false,
          child: ListTile(
            leading: Icon(
              accountChannelIcon(channel ?? '自定义'),
              color: accountChannelColor(context, channel ?? '自定义'),
            ),
            title: ParameterText(
              kind == null || channel == null ? '选择账户类型' : '$channel · $kind',
            ),
            subtitle: balanceLocked ? const Text('已有流水或余额调整，账户类型及币种受保护') : null,
            trailing: widget.initialChannel == null
                ? TextButton(
                    onPressed: () =>
                        setState(() => showTypeChoices = !showTypeChoices),
                    child: Text(showTypeChoices ? '收起' : '更换'),
                  )
                : null,
          ),
        ),
      if (showTypeChoices)
        AccountTypePicker(
          kind: kind,
          channel: channel,
          allowedKind: balanceLocked || widget.initialKind == '债务'
              ? kind
              : null,
          allowedChannel: balanceLocked && kind == '债务'
              ? channel
              : widget.initialChannel,
          onSelected: selectType,
        ),
      if (isBankChannel(channel)) ...[
        const ParameterText('银行类型（选填）'),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final entry in bankLabels.entries)
              ChoiceChip(
                key: ValueKey('account-bank-${entry.key}'),
                label: Text(entry.value),
                selected: bank == entry.key,
                onSelected: (_) => setState(() {
                  bank = entry.key;
                  if (widget.account == null &&
                      widget.initialName == null &&
                      name.text == channel &&
                      bank.isNotEmpty) {
                    name.text = entry.value;
                  }
                }),
              ),
          ],
        ),
      ],
      const Text('账户头像'),
      Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final entry in avatarLabels.entries)
            ChoiceChip(
              label: Text(entry.value),
              selected: avatar == entry.key,
              onSelected: (_) => setState(() => avatar = entry.key),
            ),
        ],
      ),
      if (channel == '自定义')
        TextField(
          controller: custom,
          maxLength: 40,
          decoration: const InputDecoration(labelText: '自定义类别'),
        ),
      TextField(
        controller: opening,
        enabled: !balanceLocked,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        decoration: InputDecoration(
          labelText: kind == '投资理财' ? '买入价 / 期初持有成本' : '初始余额',
          helperText: kind == '债务'
              ? '填待收或待还金额，通常填正数；无期初债务填 0。'
              : '必填；无余额请填 0，信贷欠款填负数。已有流水后可使用余额调整。',
        ),
      ),
      if (kind == '信贷账户')
        TextField(
          controller: creditLimit,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: '信贷额度（选填）',
            helperText: '空白表示未设置，额度不计入资产',
          ),
        ),
      if (kind == '投资理财')
        TextField(
          controller: unitPrice,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: '买入单价（选填）',
            helperText: '最多 8 位小数；仅记录买入成本，不获取实时价格。',
          ),
        ),
    ],
  );
}
