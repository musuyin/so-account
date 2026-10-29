import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/providers.dart';
import '../../../app/widgets.dart';
import '../../ledger/presentation/account_avatar.dart';
import '../../ledger/presentation/account_detail_page.dart';

class ArchivedAccountsPage extends ConsumerStatefulWidget {
  const ArchivedAccountsPage({super.key});

  @override
  ConsumerState<ArchivedAccountsPage> createState() => _ArchivedAccountsState();
}

class _ArchivedAccountsState extends ConsumerState<ArchivedAccountsPage> {
  final restoring = <String>{};

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('归档账户')),
    body: DataView(
      builder: (data) {
        final accounts = data.accounts.where((a) => a.isArchived).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('归档账户保留全部历史记录，仍计入历史收支与报表；不显示在资产汇总和新记账选择中。恢复后可继续使用。'),
            const SizedBox(height: 12),
            if (accounts.isEmpty)
              const EmptyState('暂无归档账户', '在账户操作中选择归档，即可在这里查看和恢复。'),
            for (final account in accounts)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: AccountAvatar(account: account),
                        title: Text(account.name),
                        subtitle: ParameterText(
                          '${account.kind} · ${account.channel == '自定义' ? account.customChannel : account.channel} · ${account.currency}',
                        ),
                        onTap: () => openForm(
                          context,
                          AccountDetailPage(id: account.id),
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => openForm(
                              context,
                              AccountDetailPage(id: account.id),
                            ),
                            icon: const Icon(Icons.receipt_long_outlined),
                            label: const Text('历史明细'),
                          ),
                          FilledButton.icon(
                            onPressed: restoring.contains(account.id)
                                ? null
                                : () async {
                                    setState(() => restoring.add(account.id));
                                    await perform(
                                      context,
                                      () => ref
                                          .read(ledgerProvider)
                                          .restoreAccount(account.id),
                                      success: '账户已恢复',
                                    );
                                    if (mounted) {
                                      setState(
                                        () => restoring.remove(account.id),
                                      );
                                    }
                                  },
                            icon: const Icon(Icons.unarchive_outlined),
                            label: const Text('恢复账户'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}
