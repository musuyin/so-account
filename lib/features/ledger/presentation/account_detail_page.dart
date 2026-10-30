import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/providers.dart';

import '../../../app/widgets.dart';
import '../../../core/money/money.dart';
import '../../../core/time/business_date.dart';
import '../domain/account_activity.dart';
import '../domain/entry_kind.dart';
import '../domain/banks.dart';
import 'accounts_page.dart';
import 'balance_adjustment_form.dart';
import 'entry_form.dart';
import 'account_actions.dart';
import 'finance_page.dart';

class AccountDetailPage extends ConsumerStatefulWidget {
  const AccountDetailPage({super.key, required this.id});
  final String id;
  @override
  ConsumerState<AccountDetailPage> createState() => _AccountDetailState();
}

class _AccountDetailState extends ConsumerState<AccountDetailPage> {
  DateTime month = DateTime.now();
  String kind = '', search = '';
  bool allDates = false;
  int limit = 100;
  @override
  Widget build(BuildContext context) {
    final query = (
      id: widget.id,
      month: allDates ? null : monthKey(month),
      kind: kind,
      search: search,
      limit: limit,
    );
    return QueryView<AccountLedgerView>(
      value: ref.watch(accountLedgerProvider(query)),
      retry: () => ref.invalidate(accountLedgerProvider(query)),
      builder: (view) {
        final data = view.data;
        final account = data.accounts
            .where((a) => a.id == widget.id)
            .firstOrNull;
        if (account == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('账户')),
            body: const EmptyState('账户已不存在', '返回查看其他账户。'),
          );
        }
        final hidden = ref.watch(assetAmountsHiddenProvider);
        String display(int amount, String _) =>
            hidden ? '••••' : decimalMoney(amount, account.currency);
        final transactionTotal = view.transactions;
        final corrections = view.corrections;
        final balance = account.openingBalance + transactionTotal + corrections;
        String description(AccountActivity row) {
          final entry = row.entry;
          if (entry == null) return row.note;
          final others = {
            entry.accountId,
            entry.targetAccountId,
            entry.debtAccountId,
          }.whereType<String>().where((id) => id != account.id);
          final names = others
              .map(
                (id) =>
                    data.accounts.where((a) => a.id == id).firstOrNull?.name,
              )
              .whereType<String>();
          return [
            if (entry.categoryId != null) data.category(entry.categoryId),
            ...names,
            if (entry.note.isNotEmpty) entry.note,
          ].join('\n');
        }

        final rows = view.rows;
        final change = view.change;
        return Scaffold(
          appBar: AppBar(
            title: Text('${account.name}  ${account.currency}'),
            actions: [
              IconButton(
                tooltip: hidden ? '显示金额' : '隐藏金额',
                onPressed: () =>
                    ref.read(assetAmountsHiddenProvider.notifier).toggle(),
                icon: Icon(hidden ? Icons.visibility_off : Icons.visibility),
              ),
              if (!account.isArchived)
                IconButton(
                  tooltip: '余额调整',
                  onPressed: () => openForm(
                    context,
                    BalanceAdjustmentForm(account: account, balance: balance),
                  ),
                  icon: const Icon(Icons.balance_outlined),
                ),
              if (!account.isArchived)
                IconButton(
                  tooltip: '编辑账户',
                  onPressed: () =>
                      openForm(context, AccountForm(account: account)),
                  icon: const Icon(Icons.edit_outlined),
                ),
              AccountActionsButton(account: account),
            ],
          ),
          floatingActionButton: account.isArchived
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => openForm(
                    context,
                    EntryForm(
                      initialAccountId:
                          account.kind == '债务' || account.kind == '投资理财'
                          ? null
                          : account.id,
                      initialTargetId: account.kind == '投资理财'
                          ? account.id
                          : null,
                      initialKind: account.kind == '投资理财'
                          ? EntryKind.invest
                          : account.kind == '债务'
                          ? (account.channel == '应付款'
                                ? EntryKind.borrow
                                : account.channel == '报销'
                                ? EntryKind.reimburse
                                : EntryKind.lend)
                          : EntryKind.expense,
                      initialCurrency: account.currency,
                      initialDebtAccountId: account.kind == '债务'
                          ? account.id
                          : null,
                      initialCounterparty: account.kind == '债务'
                          ? account.name
                          : null,
                    ),
                  ),
                  icon: const Icon(Icons.add),
                  label: Text(
                    account.kind == '投资理财'
                        ? '投资投入'
                        : account.channel == '报销'
                        ? '添加报销'
                        : account.kind == '债务'
                        ? '新增借贷'
                        : '记一笔',
                  ),
                ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
            children: [
              if (account.isArchived)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text('此账户已归档，历史记录只读。可通过右上角账户操作或设置中的归档账户恢复。'),
                ),
              Card(
                borderOnForeground: false,
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('账面余额'),
                      if (account.creditLimit != null) ...[
                        ParameterRow([
                          '信贷额度',
                          display(account.creditLimit!, account.currency),
                        ]),
                        ParameterRow([
                          '账面已用',
                          display(balance < 0 ? -balance : 0, account.currency),
                        ]),
                        ParameterRow([
                          '可用额度',
                          display(
                            account.creditLimit! + (balance < 0 ? balance : 0),
                            account.currency,
                          ),
                        ]),
                      ],
                      if (account.bank.isNotEmpty)
                        Text(bankLabels[account.bank] ?? '其他银行'),
                      Text(
                        display(balance, account.currency),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '期初余额  ${display(account.openingBalance, account.currency)}',
                      ),
                      Text(
                        '交易净变动  ${display(transactionTotal, account.currency)}',
                      ),
                      Text('余额调整  ${display(corrections, account.currency)}'),
                    ],
                  ),
                ),
              ),
              if (account.kind == '投资理财' || account.channel == '报销')
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: FilledButton.tonalIcon(
                    onPressed: () => openForm(
                      context,
                      FinancePage(
                        investment: account.kind == '投资理财',
                        currency: account.currency,
                        accountId: account.id,
                      ),
                    ),
                    icon: Icon(
                      account.kind == '投资理财'
                          ? Icons.stacked_line_chart
                          : Icons.receipt_outlined,
                    ),
                    label: Text(
                      account.kind == '投资理财'
                          ? '管理理财产品 / 投入 / 收回'
                          : '管理报销 / 收到回款',
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('按月'),
                    selected: !allDates,
                    onSelected: (_) => setState(() {
                      allDates = false;
                      limit = 100;
                    }),
                  ),
                  ChoiceChip(
                    label: const Text('全部时间'),
                    selected: allDates,
                    onSelected: (_) => setState(() {
                      allDates = true;
                      limit = 100;
                    }),
                  ),
                ],
              ),
              if (!allDates)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      tooltip: '上个月',
                      onPressed: () => setState(
                        () => month = DateTime(month.year, month.month - 1),
                      ),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    TextButton(
                      onPressed: () => setState(() => month = DateTime.now()),
                      child: Text(monthKey(month)),
                    ),
                    IconButton(
                      tooltip: '下个月',
                      onPressed: () => setState(
                        () => month = DateTime(month.year, month.month + 1),
                      ),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ClearableSearch(
                value: search,
                hint: '搜索备注、分类或对方账户',
                onChanged: (v) => setState(() {
                  search = v;
                  limit = 100;
                }),
              ),
              DropdownButton<String>(
                value: kind,
                isExpanded: true,
                onChanged: (v) => setState(() {
                  kind = v!;
                  limit = 100;
                }),
                items: [
                  const DropdownMenuItem(value: '', child: Text('全部记录类型')),
                  for (final entryKind in EntryKind.values)
                    DropdownMenuItem(
                      value: entryKind.name,
                      child: Text(entryKind.label),
                    ),
                  const DropdownMenuItem(
                    value: 'adjustment',
                    child: Text('余额调整'),
                  ),
                ],
              ),
              ParameterRow([
                '筛选结果 ${view.count} 笔',
                '净变动 ${display(change, account.currency)}',
              ]),
              if (rows.isEmpty)
                const EmptyState('暂无符合条件的记录', '更换月份、类型或关键词后重试。'),
              for (final row in rows)
                Card(
                  borderOnForeground: false,
                  child: ListTile(
                    title: ParameterRow([
                      row.label,
                      '${row.delta > 0 ? '+' : ''}${display(row.delta, account.currency)}',
                    ]),
                    subtitle: Text(
                      [
                        row.date,
                        description(row),
                      ].where((part) => part.isNotEmpty).join('\n'),
                    ),
                    isThreeLine: description(row).isNotEmpty,
                    trailing: row.entry == null
                        ? const Icon(Icons.tune)
                        : const Icon(Icons.chevron_right),
                    onTap: row.entry == null
                        ? null
                        : () => openForm(context, EntryForm(entry: row.entry)),
                  ),
                ),
              if (view.count > rows.length)
                TextButton(
                  onPressed: () => setState(() => limit += 100),
                  child: const Text('显示更多记录'),
                ),
            ],
          ),
        );
      },
    );
  }
}
