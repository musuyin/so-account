import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/providers.dart';
import '../../../app/widgets.dart';
import '../../../core/money/money.dart';
import '../domain/debt_relationship.dart';
import '../domain/entry_kind.dart';
import 'accounts_page.dart';
import 'entry_form.dart';

// Preserve the existing route entry while folding people into debt accounts.
class PeopleDebtsPage extends ConsumerStatefulWidget {
  const PeopleDebtsPage({super.key});
  @override
  ConsumerState<PeopleDebtsPage> createState() => _DebtAccountsState();
}

class _DebtAccountsState extends ConsumerState<PeopleDebtsPage> {
  String currency = 'CNY';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('债务')),
    body: DataView(
      builder: (data) {
        final balances = ref.watch(balancesProvider).value ?? {};
        final accounts = data.accounts
            .where((a) => a.kind == '债务' && a.currency == currency)
            .toList();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButton<String>(
              value: currency,
              items: [
                for (final value in currencies)
                  DropdownMenuItem(value: value, child: Text(value)),
              ],
              onChanged: (v) => setState(() => currency = v!),
            ),
            for (final side in accountTypes['债务']!) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  side,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                subtitle: Text(
                  '余额合计 ${money(accounts.where((a) => a.channel == side).fold<int>(0, (sum, a) => sum + (balances[a.id] ?? a.openingBalance)), currency)}',
                ),
                trailing: IconButton(
                  tooltip: '新增$side账户',
                  icon: const Icon(Icons.add),
                  onPressed: () => openForm(
                    context,
                    AccountForm(initialKind: '债务', initialChannel: side),
                  ),
                ),
              ),
              for (final account in accounts.where((a) => a.channel == side))
                Card(
                  child: ExpansionTile(
                    title: Text(account.name),
                    subtitle: Text(
                      '${side == '应付款' ? '待偿还' : '待收回'} ${money(balances[account.id] ?? account.openingBalance, currency)}',
                    ),
                    children: [
                      TextButton(
                        onPressed: () =>
                            openForm(context, AccountForm(account: account)),
                        child: const Text('编辑账户'),
                      ),
                      TextButton(
                        onPressed: () => openForm(
                          context,
                          EntryForm(
                            initialKind: side == '应付款'
                                ? EntryKind.borrow
                                : EntryKind.lend,
                            initialDebtAccountId: account.id,
                          ),
                        ),
                        child: Text(side == '应付款' ? '新增借入' : '新增借出 / 待收'),
                      ),
                      for (final debt in data.entries.where(
                        (e) =>
                            e.debtAccountId == account.id &&
                            ['borrow', 'lend'].contains(e.kind),
                      ))
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  '${debt.kind == 'borrow' ? '借入' : '借出'} ${money(debt.amount, currency)}',
                                ),
                                subtitle: Text(
                                  '${debt.date} · 剩余 ${money(debtRemaining(debt, data.entries), currency)}',
                                ),
                                onTap: () =>
                                    openForm(context, EntryForm(entry: debt)),
                              ),
                              if (debtRemaining(debt, data.entries) > 0)
                                TextButton(
                                  onPressed: () => openForm(
                                    context,
                                    EntryForm(
                                      initialKind: debt.kind == 'borrow'
                                          ? EntryKind.repay
                                          : EntryKind.collect,
                                      initialDebt: debt,
                                    ),
                                  ),
                                  child: Text(
                                    debt.kind == 'borrow' ? '偿还借入' : '收回借出',
                                  ),
                                ),
                              for (final payment in data.entries.where(
                                (e) => e.debtId == debt.id,
                              ))
                                ListTile(
                                  title: Text(
                                    '${payment.date} · ${money(payment.amount, currency)}',
                                  ),
                                  subtitle: Text(
                                    data.account(payment.accountId).name,
                                  ),
                                  onTap: () => openForm(
                                    context,
                                    EntryForm(entry: payment),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      if (!data.entries.any(
                        (e) => e.debtAccountId == account.id,
                      ))
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('期初债务可通过转账偿还或收回；有分笔借贷时请选择对应记录结算。'),
                        ),
                    ],
                  ),
                ),
            ],
          ],
        );
      },
    ),
  );
}
