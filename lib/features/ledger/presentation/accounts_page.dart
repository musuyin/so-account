import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/providers.dart';
import '../../../app/widgets.dart';
import '../../../core/money/money.dart';
import '../../../data/database/app_database.dart';
import '../domain/entry_kind.dart';
import '../domain/asset_summary.dart';
import 'account_avatar.dart';
import 'people_debts_page.dart';
import 'balance_adjustment_form.dart';
import '../../goals/presentation/goals_page.dart';
import 'account_detail_page.dart';

class AccountsPage extends ConsumerStatefulWidget {
  const AccountsPage({super.key});
  @override
  ConsumerState<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends ConsumerState<AccountsPage> {
  String currency = 'CNY';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('账户'),
      actions: [
        IconButton(
          tooltip: '心愿与攒钱',
          onPressed: () => openForm(context, const GoalsPage()),
          icon: const Icon(Icons.savings_outlined),
        ),
        IconButton(
          tooltip: '债务',
          onPressed: () => openForm(context, const PeopleDebtsPage()),
          icon: const Icon(Icons.people_outline),
        ),
        IconButton(
          tooltip: '新增账户',
          onPressed: () => openForm(context, const AccountForm()),
          icon: const Icon(Icons.add),
        ),
      ],
    ),
    body: DataView(
      builder: (data) {
        final balanceState = ref.watch(balancesProvider);
        if (balanceState.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (balanceState.hasError) return const Center(child: Text('余额读取失败'));
        final balances = balanceState.value ?? {};
        final accounts = data.accounts
            .where((a) => a.currency == currency)
            .toList();
        final receivable = accounts
            .where((a) => a.kind == '债务' && a.channel != '应付款')
            .fold<int>(
              0,
              (sum, a) => sum + (balances[a.id] ?? a.openingBalance),
            );
        final payable = accounts
            .where((a) => a.kind == '债务' && a.channel == '应付款')
            .fold<int>(
              0,
              (sum, a) => sum + (balances[a.id] ?? a.openingBalance),
            );
        final totals = AssetSummary.calculate(
          accounts.map(
            (a) => assetBalance(a.channel, balances[a.id] ?? a.openingBalance),
          ),
        );
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: DropdownButton<String>(
                value: currency,
                items: currencies
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => setState(() => currency = v!),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('净资产'),
                    Text(
                      decimalMoney(totals.net, currency),
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '总资产\n${decimalMoney(totals.assets, currency)}',
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '总负债\n${decimalMoney(totals.liabilities, currency)}',
                          ),
                        ),
                      ],
                    ),
                    if (receivable > 0 || payable > 0) ...[
                      const SizedBox(height: 12),
                      Text(
                        '含待收回 ${decimalMoney(receivable, currency)} · 待偿还 ${decimalMoney(payable, currency)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (accounts.isEmpty) const EmptyState('暂无账户', '添加账户后开始记账。'),
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: const Text('债务'),
              subtitle: Text(
                '待收回 ${money(receivable, currency)} · 待偿还 ${money(payable, currency)}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openForm(context, const PeopleDebtsPage()),
            ),
            for (final kind in accountKinds)
              if (accounts.any((a) => a.kind == kind))
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  kind,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                              Text(
                                money(
                                  accounts
                                      .where((a) => a.kind == kind)
                                      .fold<int>(
                                        0,
                                        (s, a) =>
                                            s +
                                            assetBalance(
                                              a.channel,
                                              balances[a.id] ??
                                                  a.openingBalance,
                                            ),
                                      ),
                                  currency,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(),
                        for (final channel in accountTypes[kind]!)
                          if (accounts.any(
                            (a) => a.kind == kind && a.channel == channel,
                          )) ...[
                            ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              title: Text(channel),
                              trailing: Text(
                                money(
                                  accounts
                                      .where(
                                        (a) =>
                                            a.kind == kind &&
                                            a.channel == channel,
                                      )
                                      .fold<int>(
                                        0,
                                        (sum, a) =>
                                            sum +
                                            (balances[a.id] ??
                                                a.openingBalance),
                                      ),
                                  currency,
                                ),
                              ),
                            ),
                            for (final account in accounts.where(
                              (a) => a.kind == kind && a.channel == channel,
                            ))
                              ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                leading: AccountAvatar(account: account),
                                title: Text(account.name),
                                subtitle: Text(
                                  '${account.channel == '自定义' && account.customChannel.isNotEmpty ? account.customChannel : account.channel} · ${money(balances[account.id] ?? account.openingBalance, currency)}${account.unitPrice == null ? '' : '\n买入单价 ${account.unitPrice} ${account.currency} · 按成本记录'}',
                                ),
                                onTap: () => openForm(
                                  context,
                                  AccountDetailPage(id: account.id),
                                ),
                                trailing: IconButton(
                                  tooltip: '删除账户',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () async {
                                    if (await confirm(
                                          context,
                                          '删除账户？',
                                          '已有流水的账户不能删除。',
                                        ) &&
                                        context.mounted) {
                                      await perform(
                                        context,
                                        () => ref
                                            .read(ledgerProvider)
                                            .deleteAccount(account.id),
                                      );
                                    }
                                  },
                                ),
                              ),
                          ],
                      ],
                    ),
                  ),
                ),
          ],
        );
      },
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => openForm(context, const AccountForm()),
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
  });
  final Account? account;
  final String? initialName;
  final String? importContext;
  final String? initialKind, initialChannel;
  @override
  ConsumerState<AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends ConsumerState<AccountForm> {
  late final name = TextEditingController(
    text: widget.account?.name ?? widget.initialName,
  );
  late String? currency =
      widget.account?.currency ?? (widget.importContext == null ? 'CNY' : null);
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
  late final unitPrice = TextEditingController(text: widget.account?.unitPrice);
  late final opening = TextEditingController(
    text: widget.importContext == null
        ? decimalMoney(widget.account?.openingBalance ?? 0, currency ?? 'CNY')
        : '',
  );
  late String avatar = widget.account?.avatar ?? '';
  bool saving = false;
  bool get balanceLocked =>
      widget.account != null &&
      (ref
              .watch(snapshotProvider)
              .value
              ?.entries
              .any(
                (entry) =>
                    entry.accountId == widget.account!.id ||
                    entry.targetAccountId == widget.account!.id ||
                    entry.debtAccountId == widget.account!.id,
              ) ??
          false);
  @override
  void dispose() {
    name.dispose();
    opening.dispose();
    custom.dispose();
    unitPrice.dispose();
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
              customChannel: custom.text,
              unitPrice: unitPrice.text,
            );
      });
      if (mounted && context.mounted) {
        setState(() => saving = false);
        if (ok) Navigator.pop(context, savedId);
      }
    },
    children: [
      if (widget.importContext != null)
        Card(
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
      DropdownButtonFormField<String>(
        initialValue: avatar,
        decoration: const InputDecoration(labelText: '账户头像'),
        items: avatarLabels.entries
            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
            .toList(),
        onChanged: (v) => setState(() => avatar = v!),
      ),
      DropdownButtonFormField<String>(
        initialValue: kind,
        decoration: const InputDecoration(labelText: '账户类型'),
        items: accountKinds
            .map((v) => DropdownMenuItem(value: v, child: Text(v)))
            .toList(),
        onChanged: balanceLocked || widget.initialKind == '债务'
            ? null
            : (v) => setState(() {
                kind = v!;
                if (!accountTypes[kind]!.contains(channel)) channel = null;
              }),
      ),
      DropdownButtonFormField<String>(
        key: ValueKey('account-channel-$kind-$channel'),
        initialValue: channel,
        decoration: const InputDecoration(labelText: '类别'),
        items: [
          for (final value in accountTypes[kind] ?? <String>[])
            DropdownMenuItem(value: value, child: Text(value)),
        ],
        onChanged:
            kind == null ||
                (balanceLocked && kind == '债务') ||
                widget.initialChannel != null
            ? null
            : (v) => setState(() => channel = v!),
      ),
      if (channel == '自定义')
        TextField(
          controller: custom,
          maxLength: 40,
          decoration: const InputDecoration(labelText: '自定义类别'),
        ),
      DropdownButtonFormField<String>(
        initialValue: currency,
        decoration: const InputDecoration(labelText: '币种'),
        items: currencies
            .map((v) => DropdownMenuItem(value: v, child: Text(v)))
            .toList(),
        onChanged: balanceLocked ? null : (v) => setState(() => currency = v!),
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
