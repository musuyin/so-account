import 'package:flutter/material.dart';

import '../../../app/theme/app_typography.dart';
import '../../../core/money/money.dart';
import '../../../data/database/app_database.dart';
import 'calendar_heatmap.dart';

class AccountPickerTile extends StatelessWidget {
  const AccountPickerTile({
    super.key,
    required this.account,
    required this.balance,
    required this.hidden,
    required this.selected,
    required this.onTap,
  });

  final Account account;
  final int? balance;
  final bool hidden, selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = hidden
        ? '••••'
        : balance == null
        ? '读取中'
        : decimalMoney(balance!, account.currency);
    final amountStyle = AppTypography.amount.copyWith(
      color: hidden || balance == null || balance == 0
          ? theme.colorScheme.onSurfaceVariant
          : balance! > 0
          ? calendarIncomeColor(theme.brightness)
          : calendarExpenseColor(theme.brightness),
    );
    return ListTile(
      key: ValueKey('account-picker-${account.id}'),
      selected: selected,
      onTap: onTap,
      title: LayoutBuilder(
        builder: (context, constraints) {
          final identity = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (selected) ...[
                    const Icon(Icons.check, size: 16),
                    const SizedBox(width: 6),
                  ],
                  Expanded(child: Text(account.name)),
                ],
              ),
              Text(
                '${account.channel} · ${account.currency}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
          final amount = Text(
            text,
            key: ValueKey('account-picker-balance-${account.id}'),
            textAlign: TextAlign.right,
            style: amountStyle,
            semanticsLabel: hidden
                ? '余额已隐藏'
                : balance == null
                ? '余额读取中'
                : '余额 $text',
          );
          final scaler = MediaQuery.textScalerOf(context);
          final measure = TextPainter(
            text: TextSpan(
              text: text,
              style: DefaultTextStyle.of(context).style.merge(amountStyle),
            ),
            textDirection: TextDirection.ltr,
            textScaler: scaler,
          )..layout();
          final stack =
              constraints.maxWidth <
              measure.width + scaler.scale(52) + (selected ? 22 : 0) + 12;
          measure.dispose();
          return stack
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    identity,
                    const SizedBox(height: 4),
                    Align(alignment: Alignment.centerRight, child: amount),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: identity),
                    const SizedBox(width: 12),
                    amount,
                  ],
                );
        },
      ),
    );
  }
}
