import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/providers.dart';
import '../../../app/widgets.dart';
import '../../../core/money/money.dart';
import '../../../data/database/app_database.dart';
import '../domain/debt_relationship.dart';
import '../domain/account_activity.dart';
import '../domain/entry_kind.dart';
import 'accounts_page.dart';
import 'entry_form.dart';

class FinancePage extends ConsumerWidget {
  const FinancePage({
    super.key,
    required this.investment,
    required this.currency,
    this.accountId,
  });
  final bool investment;
  final String currency;
  final String? accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => DataView(
    builder: (data) {
      final hidden = ref.watch(assetAmountsHiddenProvider);
      String amount(int value) => hidden ? '••••' : money(value, currency);
      final accounts = data.accounts
          .where(
            (a) =>
                a.currency == currency &&
                (accountId == null ? !a.isArchived : a.id == accountId) &&
                (investment
                    ? a.kind == '投资理财'
                    : a.kind == '债务' && a.channel == '报销'),
          )
          .toList();
      return Scaffold(
        appBar: AppBar(
          title: Text(investment ? '理财管理' : '报销管理'),
          actions: [
            IconButton(
              tooltip: hidden ? '显示金额' : '隐藏金额',
              onPressed: () =>
                  ref.read(assetAmountsHiddenProvider.notifier).toggle(),
              icon: Icon(hidden ? Icons.visibility_off : Icons.visibility),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (accountId == null)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => openForm(
                    context,
                    AccountForm(
                      initialKind: investment ? '投资理财' : '债务',
                      initialChannel: investment ? '基金' : '报销',
                      initialCurrency: currency,
                    ),
                  ),
                  icon: const Icon(Icons.add),
                  label: Text(investment ? '添加理财账户' : '添加报销对象'),
                ),
              ),
            if (accounts.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('暂无账户，请先添加。'),
              ),
            for (final account in accounts)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        account.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      ParameterRow([
                        investment ? '账户持有成本' : '账户待收合计',
                        amount(
                          account.openingBalance +
                              data.entries.fold<int>(
                                0,
                                (s, e) => s + accountEntryDelta(account, e),
                              ) +
                              data.adjustments
                                  .where((a) => a.accountId == account.id)
                                  .fold<int>(0, (s, a) => s + a.delta),
                        ),
                      ]),
                      if (account.openingBalance != 0)
                        ParameterRow([
                          investment ? '期初成本' : '期初待收',
                          amount(account.openingBalance),
                        ]),
                      if (account.isArchived) const Text('账户已归档，历史记录只读。'),
                      if (!account.isArchived)
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: () => openForm(
                                context,
                                EntryForm(
                                  initialKind: investment
                                      ? EntryKind.invest
                                      : EntryKind.reimburse,
                                  initialDebtAccountId: investment
                                      ? null
                                      : account.id,
                                  initialTargetId: investment
                                      ? account.id
                                      : null,
                                  initialCurrency: currency,
                                ),
                              ),
                              icon: const Icon(Icons.add),
                              label: Text(investment ? '投资投入' : '添加报销'),
                            ),
                            if (investment)
                              OutlinedButton.icon(
                                onPressed: () => openForm(
                                  context,
                                  ProductForm(accountId: account.id),
                                ),
                                icon: const Icon(Icons.add_chart),
                                label: const Text('添加产品'),
                              ),
                          ],
                        ),
                      if (investment) ...[
                        const Text('产品剩余投入成本'),
                        for (final product in data.investmentProducts.where(
                          (p) => p.accountId == account.id,
                        ))
                          Builder(
                            builder: (context) {
                              final entries = data.entries
                                  .where(
                                    (e) => e.investmentProductId == product.id,
                                  )
                                  .toList();
                              final cost = entries.fold<int>(
                                0,
                                (sum, e) =>
                                    sum +
                                    (e.kind == 'invest' ? e.amount : -e.amount),
                              );
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    ParameterRow([
                                      product.name,
                                      product.kind,
                                      amount(cost),
                                    ]),
                                    if (!account.isArchived)
                                      Wrap(
                                        spacing: 8,
                                        children: [
                                          TextButton(
                                            onPressed: () => openForm(
                                              context,
                                              EntryForm(
                                                initialKind: EntryKind.invest,
                                                initialTargetId: account.id,
                                                initialProductId: product.id,
                                                initialCurrency: currency,
                                              ),
                                            ),
                                            child: const Text('投入'),
                                          ),
                                          TextButton(
                                            onPressed: cost <= 0
                                                ? null
                                                : () => openForm(
                                                    context,
                                                    EntryForm(
                                                      initialKind:
                                                          EntryKind.redeem,
                                                      initialTargetId:
                                                          account.id,
                                                      initialProductId:
                                                          product.id,
                                                      initialCurrency: currency,
                                                    ),
                                                  ),
                                            child: const Text('收回成本'),
                                          ),
                                          TextButton(
                                            onPressed: () => openForm(
                                              context,
                                              ProductForm(
                                                accountId: account.id,
                                                product: product,
                                              ),
                                            ),
                                            child: const Text('编辑产品'),
                                          ),
                                          if (entries.isEmpty)
                                            TextButton(
                                              onPressed: () => perform(
                                                context,
                                                () => ref
                                                    .read(ledgerProvider)
                                                    .deleteInvestmentProduct(
                                                      product.id,
                                                    ),
                                              ),
                                              child: const Text('删除产品'),
                                            ),
                                        ],
                                      ),
                                    for (final e in entries)
                                      ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: ParameterRow([
                                          EntryKind.values.byName(e.kind).label,
                                          amount(e.amount),
                                        ]),
                                        subtitle: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            ParameterRow([
                                              e.date,
                                              data.account(e.accountId).name,
                                            ]),
                                            if (e.unitPrice != null)
                                              Text(
                                                hidden
                                                    ? '单价 ••••'
                                                    : '手填单价 ${e.unitPrice}',
                                              ),
                                            if (e.note.isNotEmpty) Text(e.note),
                                          ],
                                        ),
                                        trailing: const Icon(
                                          Icons.chevron_right,
                                        ),
                                        onTap: () => openForm(
                                          context,
                                          EntryForm(entry: e),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        if (!data.investmentProducts.any(
                          (p) => p.accountId == account.id,
                        ))
                          const Text('暂无产品。期初持有成本仍保留在账户余额中。'),
                      ] else ...[
                        for (final entry in data.entries.where(
                          (e) =>
                              e.debtAccountId == account.id &&
                              ['reimburse', 'lend'].contains(e.kind),
                        ))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                InkWell(
                                  onTap: () => openForm(
                                    context,
                                    EntryForm(entry: entry),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      ParameterRow([
                                        entry.date,
                                        amount(entry.amount),
                                      ]),
                                      if (entry.note.isNotEmpty)
                                        Text(entry.note),
                                      ParameterRow([
                                        '待收',
                                        amount(
                                          debtRemaining(entry, data.entries),
                                        ),
                                      ]),
                                    ],
                                  ),
                                ),
                                if (!account.isArchived &&
                                    !data.hasArchivedAccount(entry) &&
                                    debtRemaining(entry, data.entries) > 0)
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: OutlinedButton(
                                      onPressed: () => openForm(
                                        context,
                                        EntryForm(
                                          initialKind: entry.kind == 'reimburse'
                                              ? EntryKind.reimbursement
                                              : EntryKind.collect,
                                          initialDebt: entry,
                                        ),
                                      ),
                                      child: const Text('收到报销款'),
                                    ),
                                  ),
                                for (final receipt in data.entries.where(
                                  (e) => e.debtId == entry.id,
                                ))
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: ParameterRow([
                                      '已回款 ${receipt.date}',
                                      amount(receipt.amount),
                                    ]),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => openForm(
                                      context,
                                      EntryForm(entry: receipt),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        if (!data.entries.any(
                          (e) =>
                              e.debtAccountId == account.id &&
                              ['reimburse', 'lend'].contains(e.kind),
                        ))
                          const Text('暂无报销条目。期初待报销款可继续通过原有转账或余额调整处理。'),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class ProductForm extends ConsumerStatefulWidget {
  const ProductForm({super.key, required this.accountId, this.product});
  final String accountId;
  final InvestmentProduct? product;
  @override
  ConsumerState<ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends ConsumerState<ProductForm> {
  late final name = TextEditingController(text: widget.product?.name);
  late String kind = widget.product?.kind ?? '股票';
  bool saving = false;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormFrame(
    title: widget.product == null ? '添加理财产品' : '编辑理财产品',
    saving: saving,
    onSave: () async {
      setState(() => saving = true);
      String? id;
      final ok = await perform(context, () async {
        id = await ref
            .read(ledgerProvider)
            .saveInvestmentProduct(
              id: widget.product?.id,
              accountId: widget.accountId,
              name: name.text,
              kind: kind,
            );
      });
      if (mounted && context.mounted) {
        setState(() => saving = false);
        if (ok) Navigator.pop(context, id);
      }
    },
    children: [
      TextField(
        controller: name,
        maxLength: 80,
        decoration: const InputDecoration(labelText: '产品名称'),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final value in accountTypes['投资理财']!)
            ChoiceChip(
              label: Text(value),
              selected: kind == value,
              onSelected: saving ? null : (_) => setState(() => kind = value),
            ),
        ],
      ),
    ],
  );
}
