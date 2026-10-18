import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/providers.dart';
import '../../../app/widgets.dart';
import '../../../core/money/money.dart';
import '../../../data/database/app_database.dart';
import '../domain/entry_kind.dart';

class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      title: const Text('我的账户'),
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
        final balances = ref.watch(balancesProvider).value ?? {};
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              '资产各有所属',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text('每个账户独立币种，余额包含初始余额与全部往来。'),
            const SizedBox(height: 20),
            if (data.accounts.isEmpty)
              const EmptyState('从一个账户开始', '添加银行卡、微信或支付宝，再记下第一笔收支。'),
            for (final account in data.accounts)
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(18),
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: Text(account.name),
                  subtitle: Text(
                    '${account.channel} · ${account.kind}\n${money(balances[account.id] ?? account.openingBalance, account.currency)}',
                  ),
                  isThreeLine: true,
                  onTap: () => openForm(context, AccountForm(account: account)),
                  trailing: IconButton(
                    tooltip: '删除账户',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (await confirm(context, '删除账户？', '已有流水的账户不能删除。') &&
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
  const AccountForm({super.key, this.account});
  final Account? account;
  @override
  ConsumerState<AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends ConsumerState<AccountForm> {
  late final name = TextEditingController(text: widget.account?.name);
  late String currency = widget.account?.currency ?? 'CNY';
  late String kind = widget.account?.kind ?? accountKinds.first;
  late String channel = widget.account?.channel ?? accountChannels.first;
  late final opening = TextEditingController(
    text: decimalMoney(widget.account?.openingBalance ?? 0, currency),
  );
  bool saving = false;
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
      final ok = await perform(
        context,
        () => ref
            .read(ledgerProvider)
            .saveAccount(
              id: widget.account?.id,
              name: name.text,
              kind: kind,
              channel: channel,
              currency: currency,
              openingBalance: parseMoney(opening.text, currency, signed: true),
            ),
      );
      if (mounted && context.mounted) {
        setState(() => saving = false);
        if (ok) Navigator.pop(context);
      }
    },
    children: [
      TextField(
        controller: name,
        maxLength: 80,
        decoration: const InputDecoration(labelText: '账户名称'),
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
        onChanged: (v) => setState(() => currency = v!),
      ),
      TextField(
        controller: opening,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        decoration: const InputDecoration(
          labelText: '初始余额',
          helperText: '欠款可输入负数；已有流水后不能改变初始余额和币种。',
        ),
      ),
    ],
  );
}
