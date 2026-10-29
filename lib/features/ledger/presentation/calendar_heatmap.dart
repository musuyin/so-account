import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_typography.dart';
import '../../../core/money/money.dart';
import '../../../core/time/business_date.dart';

String calendarMoney(int minor, String currency) =>
    decimalMoney(minor, currency);

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
    final scaler = MediaQuery.textScalerOf(context);
    final offset = month.weekday - 1;
    final count = DateTime(month.year, month.month + 1, 0).day;
    final maximum = daily.values.fold<int>(
      0,
      (v, d) => math.max(v, ((d['income'] ?? 0) - (d['expense'] ?? 0)).abs()),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.maxWidth / 7;
        // Keep text at the system size. Disclose fewer rows when it cannot fit;
        // the selected date and tooltip always retain exact income and expense.
        final dateHeight = scaler.scale(13) * 1.2;
        final amountHeight = scaler.scale(10) * 1.2;
        final available = side - 8;
        final showBoth = dateHeight + amountHeight * 2 <= available;
        final showNet = dateHeight + amountHeight <= available;
        return Column(
          key: const ValueKey('calendar-grid'),
          children: [
            Row(
              children: [
                for (final label in ['一', '二', '三', '四', '五', '六', '日'])
                  Expanded(child: Center(child: Text(label))),
              ],
            ),
            for (var week = 0; week < (offset + count + 6) ~/ 7; week++)
              Row(
                children: [
                  for (var day = 0; day < 7; day++)
                    Expanded(
                      child: SizedBox(
                        height: side,
                        child: Builder(
                          builder: (context) {
                            final index = week * 7 + day;
                            if (index < offset || index >= offset + count) {
                              return const SizedBox.shrink();
                            }
                            final date = dateKey(
                              DateTime(
                                month.year,
                                month.month,
                                index - offset + 1,
                              ),
                            );
                            final inc = daily[date]?['income'] ?? 0,
                                out = daily[date]?['expense'] ?? 0;
                            final net = inc - out;
                            final today = date == dateKey(DateTime.now());
                            final description =
                                '$date${today ? '，今天' : ''}，$currency，收入 ${decimalMoney(inc, currency)}，支出 ${decimalMoney(out, currency)}，净额 ${decimalMoney(net, currency)}';
                            Widget amount(
                              int value,
                              String sign,
                              Color color,
                            ) => Text(
                              '$sign${calendarMoney(value, currency)}',
                              softWrap: false,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: AppTypography.calendarAmount.copyWith(
                                color: color,
                              ),
                            );
                            return Semantics(
                              key: ValueKey('calendar-$date'),
                              label: description,
                              selected: selected == date,
                              button: true,
                              excludeSemantics: true,
                              child: Tooltip(
                                message: description,
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
                                        maximum,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: selected == date
                                            ? colors.primary
                                            : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.start,
                                      children: [
                                        Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            SizedBox(
                                              width: double.infinity,
                                              child: Text(
                                                '${index - offset + 1}',
                                                textAlign: TextAlign.center,
                                                softWrap: false,
                                                maxLines: 1,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  height: 1.2,
                                                ),
                                              ),
                                            ),
                                            if (today)
                                              Positioned(
                                                right: 0,
                                                top: 1,
                                                child: Icon(
                                                  Icons.circle,
                                                  size: 4,
                                                  color: colors.primary,
                                                ),
                                              ),
                                          ],
                                        ),
                                        if (showBoth) ...[
                                          if (out != 0)
                                            amount(
                                              out,
                                              '-',
                                              calendarExpenseColor(
                                                colors.brightness,
                                              ),
                                            ),
                                          if (inc != 0)
                                            amount(
                                              inc,
                                              '+',
                                              calendarIncomeColor(
                                                colors.brightness,
                                              ),
                                            ),
                                        ] else if (showNet &&
                                            (inc != 0 || out != 0))
                                          amount(
                                            net.abs(),
                                            net < 0 ? '-' : '+',
                                            net < 0
                                                ? calendarExpenseColor(
                                                    colors.brightness,
                                                  )
                                                : calendarIncomeColor(
                                                    colors.brightness,
                                                  ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
          ],
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
        children: [scale('日净支出', -1), scale('日净收入', 1)],
      ),
    );
  }
}
