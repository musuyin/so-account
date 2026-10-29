import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_typography.dart';
import '../../../core/money/money.dart';
import '../../../core/time/business_date.dart';

String calendarMoney(int minor, String currency) {
  final factor = currency == 'JPY' ? 1 : 100;
  if (minor.abs() < 10000 * factor) return decimalMoney(minor, currency);
  if (minor.abs() >= 99995000 * factor) {
    return '${(minor / factor / 100000000).toStringAsFixed(1)}亿';
  }
  return '${(minor / factor / 10000).toStringAsFixed(1)}万';
}

class LedgerCalendar extends StatelessWidget {
  const LedgerCalendar({
    super.key,
    required this.month,
    required this.currency,
    required this.daily,
    required this.selected,
    required this.onSelected,
  });
  final DateTime month;
  final String currency;
  final Map<String, Map<String, int>> daily;
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final scale = MediaQuery.textScalerOf(context);
    final painter = TextPainter(
      text: TextSpan(
        text: '-9999.99',
        style: DefaultTextStyle.of(context).style
            .merge(AppTypography.calendarAmount),
      ),
      textDirection: TextDirection.ltr,
      textScaler: scale,
    )..layout();
    final minSide = math.max(
      painter.width + 8,
      scale.scale(13) * 1.2 + scale.scale(10) * 2.4 + 12,
    );
    painter.dispose();
    final offset = month.weekday - 1;
    final count = DateTime(month.year, month.month + 1, 0).day;
    final maxNet = daily.values.fold<int>(
      0,
      (v, d) => math.max(v, ((d['income'] ?? 0) - (d['expense'] ?? 0)).abs()),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.max(minSide, constraints.maxWidth / 7);
        return SingleChildScrollView(
          key: const ValueKey('calendar-scroll'),
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: side * 7,
            child: Column(
              children: [
                Row(
                  children: [
                    for (final label in ['一', '二', '三', '四', '五', '六', '日'])
                      SizedBox(
                        width: side,
                        child: Center(child: Text(label)),
                      ),
                  ],
                ),
                Wrap(
                  children: [
                    for (var i = 0; i < ((offset + count + 6) ~/ 7) * 7; i++)
                      SizedBox(
                        width: side,
                        height: side,
                        child: i < offset || i >= offset + count
                            ? null
                            : Builder(
                                builder: (context) {
                                  final date = dateKey(
                                    DateTime(
                                      month.year,
                                      month.month,
                                      i - offset + 1,
                                    ),
                                  );
                                  final inc = daily[date]?['income'] ?? 0;
                                  final out = daily[date]?['expense'] ?? 0;
                                  final today = date == dateKey(DateTime.now());
                                  Widget amount(
                                    int value,
                                    String sign,
                                    Color color,
                                  ) => Text(
                                    value == 0
                                        ? ''
                                        : '$sign${calendarMoney(value, currency)}',
                                    style: AppTypography.calendarAmount
                                        .copyWith(color: color),
                                    maxLines: 1,
                                  );
                                  return Semantics(
                                    key: ValueKey('calendar-$date'),
                                    label:
                                        '$date${today ? '，今天' : ''}，$currency，收入 ${decimalMoney(inc, currency)}，支出 ${decimalMoney(out, currency)}，净额 ${decimalMoney(inc - out, currency)}',
                                    button: true,
                                    selected: selected == date,
                                    excludeSemantics: true,
                                    child: InkWell(
                                      onTap: () => onSelected(date),
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        margin: const EdgeInsets.all(2),
                                        decoration: BoxDecoration(
                                          color: calendarHeatColor(
                                            colors,
                                            inc,
                                            out,
                                            maxNet,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: selected == date
                                              ? Border.all(
                                                  color: colors.primary,
                                                  width: 2,
                                                )
                                              : null,
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  '${i - offset + 1}',
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    height: 1.2,
                                                  ),
                                                ),
                                                if (today)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          left: 2,
                                                        ),
                                                    child: Icon(
                                                      Icons.circle,
                                                      size: 4,
                                                      color: colors.primary,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            amount(
                                              out,
                                              '-',
                                              calendarExpenseColor(
                                                colors.brightness,
                                              ),
                                            ),
                                            amount(
                                              inc,
                                              '+',
                                              calendarIncomeColor(
                                                colors.brightness,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Color calendarIncomeColor(Brightness brightness) =>
    brightness == Brightness.dark
    ? const Color(0xFFD1F5DD)
    : const Color(0xFF0C4825);
Color calendarExpenseColor(Brightness brightness) =>
    brightness == Brightness.dark
    ? const Color(0xFFFFE4DE)
    : const Color(0xFF7A1712);

Color calendarHeatColor(
  ColorScheme colors,
  int income,
  int expense,
  int maximumNet,
) {
  final net = income - expense;
  if (income == 0 && expense == 0) return colors.surface;
  if (net == 0 || maximumNet <= 0) return colors.surfaceContainerHighest;
  final dark = colors.brightness == Brightness.dark;
  final accent = net > 0
      ? (dark ? const Color(0xFF81C995) : const Color(0xFF237A43))
      : (dark ? const Color(0xFFF28B82) : const Color(0xFFB3261E));
  final strength = math.sqrt((net.abs() / maximumNet).clamp(0, 1));
  return Color.lerp(
    dark ? colors.surfaceContainerLow : colors.surface,
    accent,
    (dark ? .10 : .08) + strength * (dark ? .28 : .30),
  )!;
}

class CalendarHeatLegend extends StatelessWidget {
  const CalendarHeatLegend({super.key});
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget scale(String label, int direction) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(width: 4),
        for (final amount in [10, 50, 100])
          Container(
            width: 9,
            height: 9,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: calendarHeatColor(
                colors,
                direction > 0 ? amount : 0,
                direction < 0 ? amount : 0,
                100,
              ),
            ),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        spacing: 12,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          scale('日净支出', -1),
          scale('日净收入', 1),
          Text(
            '浅少 · 深多 · 可左右滑动',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}
