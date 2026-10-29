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
    final scaler = MediaQuery.textScalerOf(context);
    final offset = month.weekday - 1;
    final count = DateTime(month.year, month.month + 1, 0).day;
    final maxNet = daily.values.fold<int>(
      0,
      (v, d) => math.max(v, ((d['income'] ?? 0) - (d['expense'] ?? 0)).abs()),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.maxWidth / 7;
        final textWidth = math.max(1.0, side - 14);
        final amountStyle = DefaultTextStyle.of(context).style
            .merge(AppTypography.calendarAmount);
        Size measure(String text) {
          if (text.isEmpty) return Size.zero;
          final painter = TextPainter(
            text: TextSpan(text: text, style: amountStyle),
            textDirection: TextDirection.ltr,
            textScaler: scaler,
          )..layout(maxWidth: textWidth);
          final size = painter.size;
          painter.dispose();
          return size;
        }

        bool fits(String text) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: amountStyle),
            textDirection: TextDirection.ltr,
            textScaler: scaler,
          )..layout();
          final result = painter.width <= textWidth;
          painter.dispose();
          return result;
        }

        String display(int value, String sign) {
          if (value == 0) return '';
          final exact = '$sign${calendarMoney(value, currency)}';
          if (fits(exact)) return exact;
          final units = currency == 'JPY' ? value.toDouble() : value / 100;
          if (units >= 1000) {
            final divisor = units >= 100000000
                ? 100000000
                : units >= 10000
                ? 10000
                : 1000;
            final suffix = divisor == 100000000
                ? '亿'
                : divisor == 10000
                ? '万'
                : '千';
            for (final digits in [1, 0]) {
              final number = (units / divisor)
                  .toStringAsFixed(digits)
                  .replaceFirst(RegExp(r'\.0$'), '');
              final compact = '$sign$number$suffix';
              if (fits(compact)) return compact;
            }
            return '$sign${(units / divisor).toStringAsFixed(0)}\n$suffix';
          }
          final raw = '$sign${decimalMoney(value, currency)}';
          return raw.replaceFirst('.', '\n.');
        }

        String key(int index) =>
            dateKey(DateTime(month.year, month.month, index - offset + 1));
        int value(int index, String kind) =>
            index < offset || index >= offset + count
            ? 0
            : daily[key(index)]?[kind] ?? 0;
        final weeks = (offset + count + 6) ~/ 7;
        return SizedBox(
          key: const ValueKey('calendar-grid'),
          width: constraints.maxWidth,
          child: Column(
            children: [
              Row(
                children: [
                  for (final label in ['一', '二', '三', '四', '五', '六', '日'])
                    Expanded(child: Center(child: Text(label))),
                ],
              ),
              for (var week = 0; week < weeks; week++)
                Builder(
                  builder: (context) {
                    var height = math.max(
                      side - 4,
                      scaler.scale(13) * 1.2 + 12,
                    );
                    for (var day = 0; day < 7; day++) {
                      final i = week * 7 + day;
                      height = math.max(
                        height,
                        scaler.scale(13) * 1.2 +
                            measure(display(value(i, 'expense'), '-')).height +
                            measure(display(value(i, 'income'), '+')).height +
                            20,
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var day = 0; day < 7; day++)
                          Expanded(
                            child: SizedBox(
                              height: height,
                              child: Builder(
                                builder: (context) {
                                  final i = week * 7 + day;
                                  if (i < offset || i >= offset + count) {
                                    return const SizedBox.shrink();
                                  }
                                  final date = key(i),
                                      inc = value(i, 'income'),
                                      out = value(i, 'expense');
                                  final today = date == dateKey(DateTime.now());
                                  Widget amount(
                                    int value,
                                    String sign,
                                    Color color,
                                  ) => value == 0
                                      ? const SizedBox.shrink()
                                      : Text(
                                          display(value, sign),
                                          textAlign: TextAlign.center,
                                          style: amountStyle.copyWith(
                                            color: color,
                                          ),
                                        );
                                  return Semantics(
                                    key: ValueKey('calendar-$date'),
                                    label:
                                        '$date${today ? '，今天' : ''}，$currency，收入 ${decimalMoney(inc, currency)}，支出 ${decimalMoney(out, currency)}，净额 ${decimalMoney(inc - out, currency)}',
                                    selected: selected == date,
                                    button: true,
                                    excludeSemantics: true,
                                    child: InkWell(
                                      onTap: () => onSelected(date),
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        margin: const EdgeInsets.all(2),
                                        padding: EdgeInsets.fromLTRB(
                                          2,
                                          selected == date ? 2 : 4,
                                          2,
                                          0,
                                        ),
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
                                              MainAxisAlignment.start,
                                          children: [
                                            SizedBox(
                                              width: double.infinity,
                                              child: Stack(
                                                alignment: Alignment.center,
                                                children: [
                                                  Text(
                                                    '${i - offset + 1}',
                                                    softWrap: false,
                                                    maxLines: 1,
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      height: 1.2,
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
                          ),
                      ],
                    );
                  },
                ),
            ],
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
        children: [scale('日净支出', -1), scale('日净收入', 1)],
      ),
    );
  }
}
