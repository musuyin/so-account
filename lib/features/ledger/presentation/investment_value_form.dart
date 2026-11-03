import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/providers/providers.dart';
import '../../../app/widgets.dart';
import '../../../core/money/money.dart';
import '../../../data/database/app_database.dart';

String valuationTime(int timestamp) =>
    DateFormat('yyyy-MM-dd HH:mm')
        .format(DateTime.fromMillisecondsSinceEpoch(timestamp));

class InvestmentValueSummary extends ConsumerWidget {
  const InvestmentValueSummary({super.key, required this.account});
  final Account account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(assetAmountsHiddenProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ParameterRow([
          '当前资产',
          account.currentValue == null
              ? '未更新'
              : hidden
              ? '••••'
              : money(account.currentValue!, account.currency),
        ]),
        if (account.valuedAt != null)
          Text(
            '手动更新于 ${valuationTime(account.valuedAt!)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (!account.isArchived)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () =>
                  openForm(context, InvestmentValueForm(account: account)),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('更新当前资产'),
            ),
          ),
      ],
    );
  }
}

class InvestmentValueForm extends ConsumerStatefulWidget {
  const InvestmentValueForm({super.key, required this.account});
  final Account account;

  @override
  ConsumerState<InvestmentValueForm> createState() =>
      _InvestmentValueFormState();
}

class _InvestmentValueFormState extends ConsumerState<InvestmentValueForm> {
  late final amount = TextEditingController(
    text: widget.account.currentValue == null
        ? ''
        : decimalMoney(widget.account.currentValue!, widget.account.currency),
  );
  bool saving = false;

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  Future<void> save({bool clear = false}) async {
    setState(() => saving = true);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final ok = await perform(
      context,
      () => ref
          .read(ledgerProvider)
          .updateInvestmentValue(
            accountId: widget.account.id,
            expectedCurrency: widget.account.currency,
            currentValue: clear
                ? null
                : parseMoney(amount.text, widget.account.currency),
          ),
    );
    if (mounted) {
      setState(() => saving = false);
      if (ok) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => FormFrame(
    title: '更新当前资产',
    currency: widget.account.currency,
    saving: saving,
    onSave: save,
    children: [
      Text(widget.account.name, style: Theme.of(context).textTheme.titleLarge),
      const Text('填入理财平台显示的账户总资产。买入成本单独保留，资产总览仍按成本汇总。'),
      TextField(
        controller: amount,
        enabled: !saving,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          labelText: '当前资产',
          helperText: '可填写 0；以账户币种为准。',
        ),
      ),
      if (widget.account.valuedAt != null)
        Text('上次更新 ${valuationTime(widget.account.valuedAt!)}'),
      if (widget.account.currentValue != null)
        TextButton(
          onPressed: saving ? null : () => save(clear: true),
          child: const Text('清除当前资产记录'),
        ),
    ],
  );
}
