import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/providers.dart';
import '../../../app/widgets.dart';
import '../../../core/money/money.dart';
import '../../../data/database/app_database.dart';

class BalanceAdjustmentForm extends ConsumerStatefulWidget {
  const BalanceAdjustmentForm({
    super.key,
    required this.account,
    required this.balance,
  });
  final Account account;
  final int balance;
  @override
  ConsumerState<BalanceAdjustmentForm> createState() =>
      _BalanceAdjustmentState();
}

class _BalanceAdjustmentState extends ConsumerState<BalanceAdjustmentForm> {
  late final amount = TextEditingController(
    text: decimalMoney(widget.balance, widget.account.currency),
  );
  final reason = TextEditingController();
  bool saving = false;
  bool createEntry = false;
  @override
  void dispose() {
    amount.dispose();
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DataView(
    builder: (data) {
      final history =
          data.adjustments
              .where((a) => a.accountId == widget.account.id)
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      String change() {
        try {
          return decimalMoney(
            parseMoney(amount.text, widget.account.currency, signed: true) -
                widget.balance,
            widget.account.currency,
          );
        } on FormatException {
          return '请填写有效余额';
        }
      }

      return FormFrame(
        title: '修改余额 · ${widget.account.currency}',
        saving: saving,
        onSave: () async {
          setState(() => saving = true);
          final ok = await perform(
            context,
            () => ref
                .read(ledgerProvider)
                .adjustBalance(
                  accountId: widget.account.id,
                  desiredBalance: parseMoney(
                    amount.text,
                    widget.account.currency,
                    signed: true,
                  ),
                  expectedBalance: widget.balance,
                  expectedCurrency: widget.account.currency,
                  reason: reason.text,
                  createEntry: createEntry,
                ),
          );
          if (mounted && context.mounted) {
            setState(() => saving = false);
            if (ok) Navigator.pop(context);
          }
        },
        children: [
          Text(
            widget.account.name,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            '调整前余额 ${decimalMoney(widget.balance, widget.account.currency)}',
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('生成收支条目'),
            subtitle: Text(
              widget.account.kind == '债务'
                  ? '债务账户仅对齐余额，收支记入资金账户'
                  : createEntry
                  ? '差额计入收入或支出及统计'
                  : '仅对齐余额，不影响收支统计',
            ),
            value: createEntry,
            onChanged: saving || widget.account.kind == '债务'
                ? null
                : (value) => setState(() => createEntry = value),
          ),
          if (widget.account.kind == '债务')
            const Text('调整债务账户只校正汇总余额，不改写各笔借贷的本金和已还金额。'),
          TextField(
            controller: amount,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            decoration: const InputDecoration(
              labelText: '实际余额',
              helperText: '填写核对后的真实余额；支持零和负数。',
            ),
          ),
          Text('本次变动 ${change()}'),
          TextField(
            controller: reason,
            maxLength: 200,
            decoration: const InputDecoration(labelText: '调整说明（选填）'),
          ),
          if (history.isNotEmpty) ...[
            const Text('余额调整记录（非交易流水）'),
            for (final adjustment in history.take(20))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${decimalMoney(adjustment.beforeBalance, widget.account.currency)} → ${decimalMoney(adjustment.afterBalance, widget.account.currency)}',
                ),
                subtitle: Text(
                  '${adjustment.date}${adjustment.reason.isEmpty ? '' : ' · ${adjustment.reason}'}',
                ),
              ),
          ],
        ],
      );
    },
  );
}
