import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/providers.dart';
import '../../../app/widgets.dart';
import '../../../data/database/app_database.dart';
import 'balance_adjustment_form.dart';

class AccountActionsButton extends ConsumerStatefulWidget {
  const AccountActionsButton({super.key, required this.account});
  final Account account;

  @override
  ConsumerState<AccountActionsButton> createState() => _AccountActionsState();
}

class _AccountActionsState extends ConsumerState<AccountActionsButton> {
  bool busy = false;

  Future<void> manage() async {
    final account = widget.account;
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(account.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (!account.isArchived)
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: const Text('修改账户余额'),
                  onTap: () => Navigator.pop(context, 'balance'),
                ),
              ListTile(
                leading: Icon(
                  account.isArchived
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined,
                ),
                title: Text(account.isArchived ? '恢复账户' : '归档账户'),
                subtitle: Text(
                  account.isArchived
                      ? '重新显示在账户列表，可继续记账。'
                      : '保留全部历史记录，退出资产汇总和记账选择，可在设置中恢复。',
                ),
                onTap: () => Navigator.pop(context, 'archive'),
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_forever_outlined,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: const Text('永久删除账户'),
                subtitle: const Text('删除账户及相关历史记录，此操作不可恢复。'),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'balance') {
      setState(() => busy = true);
      await perform(context, () async {
        final balances = await ref.read(ledgerProvider).balances();
        if (!mounted) return;
        final balance = balances[account.id];
        if (balance == null) throw const FormatException('账户已不存在');
        await openForm(
          context,
          BalanceAdjustmentForm(account: account, balance: balance),
        );
      });
      if (mounted) setState(() => busy = false);
      return;
    }
    if (action == 'delete') {
      final approved = await confirm(
        context,
        '永久删除「${account.name}」？',
        '此账户的收支、转账、借贷、余额调整及关联还款将全部删除，其他账户的余额与统计也会变化。物品保留，仅移除流水关联。此操作不可恢复；保留历史请选择归档。',
        confirmLabel: '永久删除',
      );
      if (!approved || !mounted) return;
    }
    setState(() => busy = true);
    final repo = ref.read(ledgerProvider);
    await perform(
      context,
      () => action == 'delete'
          ? repo.deleteAccount(account.id)
          : account.isArchived
          ? repo.restoreAccount(account.id)
          : repo.archiveAccount(account.id),
      success: action == 'delete'
          ? '账户及相关历史已删除'
          : account.isArchived
          ? '账户已恢复'
          : '账户已归档，可在设置中查看和恢复',
    );
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: '账户操作',
    onPressed: busy ? null : manage,
    icon: const Icon(Icons.more_horiz),
  );
}
