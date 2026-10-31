import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/providers.dart';
import '../../../app/widgets.dart';
import '../../../core/money/money.dart';
import '../../ledger/presentation/balance_adjustment_form.dart';

class ImportBalancesPage extends ConsumerWidget {
  const ImportBalancesPage({
    super.key,
    this.accountIds,
    this.currency,
    this.title = '导入后核对余额',
    this.includeArchived = false,
  });
  final Set<String>? accountIds;
  final String? currency;
  final String title;
  final bool includeArchived;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(assetAmountsHiddenProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: hidden ? '显示资产金额' : '隐藏资产金额',
            onPressed: () =>
                ref.read(assetAmountsHiddenProvider.notifier).toggle(),
            icon: Icon(
              hidden
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
        ],
      ),
      body: DataView(
        builder: (data) {
          final balances = ref.watch(balancesProvider);
          final accounts =
              (includeArchived ? data.accounts : data.activeAccounts)
                  .where(
                    (a) =>
                        (accountIds == null || accountIds!.contains(a.id)) &&
                        (currency == null || a.currency == currency),
                  )
                  .toList();
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text('核对各账户的真实余额。不勾选「生成收支条目」只校准余额；勾选后生成的流水会参与收支统计和回滚。'),
              if (hidden) const Text('资产金额已隐藏，显示后可核对或调整。'),
              if (balances.isLoading) const LinearProgressIndicator(),
              if (balances.hasError) const Text('余额读取失败，请返回后重试。'),
              if (accounts.isEmpty)
                const EmptyState('没有需要核对的账户', '相关账户可能已归档或删除。'),
              for (final account in accounts)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${account.name}${account.isArchived ? '（已归档）' : ''}',
                  ),
                  subtitle: Text(
                    hidden
                        ? '当前余额 ••••'
                        : balances.value?[account.id] == null
                        ? '正在读取余额'
                        : '当前余额 ${money(balances.value![account.id]!, account.currency)}',
                  ),
                  trailing: TextButton(
                    onPressed:
                        hidden ||
                            account.isArchived ||
                            balances.value?[account.id] == null
                        ? null
                        : () => perform(context, () async {
                            // Read again on tap so the form never starts from a stale preview balance.
                            final db = ref.read(databaseProvider);
                            final current =
                                await (db.select(db.accounts)
                                      ..where((a) => a.id.equals(account.id)))
                                    .getSingleOrNull();
                            if (current == null) {
                              throw const FormatException('账户已不存在');
                            }
                            final balance = (await ref
                                .read(ledgerProvider)
                                .balances())[current.id];
                            if (balance == null) {
                              throw const FormatException('余额读取失败，请重试');
                            }
                            if (context.mounted) {
                              await openForm(
                                context,
                                BalanceAdjustmentForm(
                                  account: current,
                                  balance: balance,
                                ),
                              );
                            }
                          }),
                    child: Text(account.isArchived ? '需先恢复' : '调整余额'),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('完成核对'),
              ),
            ],
          );
        },
      ),
    );
  }
}
