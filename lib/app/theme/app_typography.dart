import 'package:flutter/material.dart';

/// Shared sizes; amounts never shrink independently of their neighbours.
abstract final class AppTypography {
  static const amount = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const summary = TextStyle(
    fontSize: 21,
    fontWeight: FontWeight.w600,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const calendarAmount = TextStyle(
    fontSize: 10,
    height: 1.2,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

class MoneySummary extends StatelessWidget {
  const MoneySummary({super.key, required this.values});
  final List<({String label, String amount, Color? color})> values;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      var needed = 0.0;
      for (final value in values) {
        final painter = TextPainter(
          text: TextSpan(
            text: value.amount,
            style: DefaultTextStyle.of(context).style
                .merge(AppTypography.summary),
          ),
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        needed = needed < painter.width ? painter.width : needed;
        painter.dispose();
      }
      final columns = constraints.maxWidth >= (needed + 16) * values.length
          ? values.length
          : constraints.maxWidth >= (needed + 16) * 2
          ? 2
          : 1;
      return Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          for (final value in values)
            SizedBox(
              width: (constraints.maxWidth - (columns - 1) * 12) / columns,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value.label,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  Text(
                    value.amount,
                    style: AppTypography.summary.copyWith(color: value.color),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}
