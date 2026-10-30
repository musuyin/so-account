import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/providers.dart';
import '../../../app/widgets.dart';
import '../../../core/money/money.dart';
import '../../ledger/presentation/balance_adjustment_form.dart';

class ImportBalancesPage extends ConsumerWidget {
  const ImportBalancesPage({super.key, required this.accountIds});
  final Set<String> accountIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('导入后核对余额')),
    body: DataView(
      builder: (data) {
        final balances = ref.watch(balancesProvider);
        final accounts = data.activeAccounts
            .where((a) => accountIds.contains(a.id))
            .toList();
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (balances.isLoading) const LinearProgressIndicator(),
            if (balances.hasError) const Text('余额读取失败，请返回后重试。'),
            if (accounts.isEmpty)
              const EmptyState('没有需要核对的账户', '相关账户可能已归档或删除。'),
            for (final account in accounts)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(account.name),
                subtitle: Text(
                  balances.value?[account.id] == null
                      ? '正在读取余额'
                      : '当前余额 ${money(balances.value![account.id]!, account.currency)}',
                ),
                trailing: TextButton(
                  onPressed: balances.value?[account.id] == null
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
                  child: const Text('调整余额'),
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
