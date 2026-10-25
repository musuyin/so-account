import 'package:flutter/material.dart';

import '../domain/entry_kind.dart';

IconData accountChannelIcon(String channel) => switch (channel) {
  '现金' => Icons.payments_outlined,
  '支付宝' => Icons.account_balance_wallet_outlined,
  '微信' => Icons.forum_outlined,
  '银行卡' => Icons.credit_card,
  'QQ钱包' => Icons.chat_bubble_outline,
  '信用卡' => Icons.credit_score_outlined,
  '花呗' => Icons.local_florist_outlined,
  '京东白条' => Icons.receipt_long_outlined,
  '会员卡' => Icons.card_membership,
  '公交卡' => Icons.directions_bus_outlined,
  '饭卡' => Icons.restaurant_outlined,
  '押金' => Icons.lock_outline,
  '基金' => Icons.stacked_line_chart,
  '股票' => Icons.show_chart,
  '保险' => Icons.health_and_safety_outlined,
  '虚拟货币' => Icons.currency_bitcoin,
  '应付款' => Icons.call_made,
  '应收款' => Icons.call_received,
  '报销' => Icons.receipt_outlined,
  _ => Icons.star_outline,
};

Color accountChannelColor(BuildContext context, String channel) {
  final color = switch (channel) {
    '微信' => const Color(0xFF26864A),
    '支付宝' || '花呗' => const Color(0xFF267BB4),
    '现金' || '银行卡' => const Color(0xFFB07916),
    '信用卡' || '应付款' => const Color(0xFFAE4F58),
    '基金' || '股票' || '虚拟货币' => const Color(0xFF80659A),
    _ => Theme.of(context).colorScheme.primary,
  };
  return Theme.of(context).brightness == Brightness.dark
      ? Color.lerp(color, Colors.white, .35)!
      : color;
}

class AccountTypePicker extends StatelessWidget {
  const AccountTypePicker({
    super.key,
    required this.kind,
    required this.channel,
    required this.onSelected,
    this.allowedKind,
    this.allowedChannel,
  });
  final String? kind, channel, allowedKind, allowedChannel;
  final void Function(String kind, String channel) onSelected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
      final columns = (constraints.maxWidth / (72 * scale)).floor().clamp(2, 5);
      final width = (constraints.maxWidth - (columns - 1) * 6) / columns;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final group in accountTypes.entries)
            if (allowedKind == null || allowedKind == group.key) ...[
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
                child: Text(
                  group.key,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final value in group.value)
                    if (allowedChannel == null || allowedChannel == value)
                      SizedBox(
                        width: width,
                        child: Semantics(
                          selected: kind == group.key && channel == value,
                          button: true,
                          label: '${group.key} · $value',
                          child: InkWell(
                            key: ValueKey('account-type-${group.key}-$value'),
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => onSelected(group.key, value),
                            child: Container(
                              constraints: const BoxConstraints(minHeight: 68),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: kind == group.key && channel == value
                                    ? Theme.of(context)
                                          .colorScheme
                                          .primaryContainer
                                    : Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerLow,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: kind == group.key && channel == value
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.transparent,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    accountChannelIcon(value),
                                    size: 24,
                                    color: accountChannelColor(context, value),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    value,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            ],
        ],
      );
    },
  );
}
