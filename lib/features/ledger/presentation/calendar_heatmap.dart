import 'dart:math' as math;

import 'package:flutter/material.dart';

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
    (dark ? .14 : .08) + strength * (dark ? .32 : .30),
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
          Text('浅少 · 深多', style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}
