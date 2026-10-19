import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/providers.dart';
import '../../../app/widgets.dart';
import '../../../core/money/money.dart';
import '../../../data/database/app_database.dart';
import '../domain/entry_kind.dart';
import '../domain/asset_summary.dart';
import 'account_avatar.dart';

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
        var receivable = 0, payable = 0;
        for (final debt in data.entries.where(
          (e) =>
              ['borrow', 'lend'].contains(e.kind) &&
              data.account(e.accountId).currency == currency,
        )) {
          final remaining =
              debt.amount -
              data.entries
                  .where((e) => e.debtId == debt.id)
                  .fold<int>(0, (s, e) => s + e.amount);
          if (debt.kind == 'borrow') {
            payable += remaining;
          } else {
            receivable += remaining;
          }
        }
        final totals = AssetSummary.calculate(
          accounts.map((a) => balances[a.id] ?? a.openingBalance),
          receivable: receivable,
          payable: payable,
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
                                            (balances[a.id] ??
                                                a.openingBalance),
                                      ),
                                  currency,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(),
                        for (final account in accounts.where(
                          (a) => a.kind == kind,
                        ))
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                            ),
                            leading: AccountAvatar(account: account),
                            title: Text(account.name),
                            subtitle: Text(
                              '${account.channel} · ${money(balances[account.id] ?? account.openingBalance, currency)}',
                            ),
                            onTap: () => openForm(
                              context,
                              AccountForm(account: account),
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
  });
  final Account? account;
  final String? initialName;
  final String? importContext;
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
      (widget.importContext == null ? accountKinds.first : null);
  late String? channel =
      widget.account?.channel ??
      (widget.importContext == null ? accountChannels.first : null);
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
                    entry.targetAccountId == widget.account!.id,
              ) ??
          false);
  @override
  void dispose() {
    name.dispose();
    opening.dispose();
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
      DropdownButtonFormField<String>(
        initialValue: avatar,
        decoration: const InputDecoration(labelText: '账户头像'),
        items: avatarLabels.entries
            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
            .toList(),
        onChanged: (v) => setState(() => avatar = v!),
      ),
      DropdownButtonFormField<String>(
        initialValue: channel,
        decoration: const InputDecoration(labelText: '渠道'),
        items: accountChannels
            .map((v) => DropdownMenuItem(value: v, child: Text(v)))
            .toList(),
        onChanged: (v) => setState(() => channel = v!),
      ),
      DropdownButtonFormField<String>(
        initialValue: kind,
        decoration: const InputDecoration(labelText: '账户类型'),
        items: accountKinds
            .map((v) => DropdownMenuItem(value: v, child: Text(v)))
            .toList(),
        onChanged: (v) => setState(() => kind = v!),
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
        decoration: const InputDecoration(
          labelText: '初始余额',
          helperText: '必填；无余额请填 0，欠款填负数。已有流水后不能改变初始余额和币种。',
        ),
      ),
    ],
  );
}
