import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_typography.dart';
import '../../../core/money/money.dart';
import '../data/statistics_repository.dart';

class CategoryRingChart extends StatelessWidget {
  const CategoryRingChart({
    super.key,
    required this.categories,
    required this.colors,
    required this.currency,
    required this.total,
    this.onSelected,
  });

  final List<CategoryComparison> categories;
  final List<Color> colors;
  final String currency;
  final int total;
  final ValueChanged<int>? onSelected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final scaler = MediaQuery.textScalerOf(context);
      final amount = decimalMoney(total, currency);
      final amountStyle = DefaultTextStyle.of(context).style
          .merge(AppTypography.amount.copyWith(fontSize: 18));
      final amountMeasure = TextPainter(
        text: TextSpan(text: amount, style: amountStyle),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      // Keep the full amount at the user's text size, even for large balances.
      final width = math.max(
        constraints.maxWidth,
        (amountMeasure.width + 4) / .35,
      );
      amountMeasure.dispose();
      final radius = width * .25;
      final labelWidth = width * .24;
      final style = theme.textTheme.bodySmall!.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      );
      var angle = 0.0;
      final labels = <_RingLabel>[];
      for (var i = 0; i < categories.length; i++) {
        final category = categories[i];
        final sweep = category.amount / total * math.pi * 2;
        final middle = angle + sweep / 2;
        final percentage =
            '${(category.amount / total * 100).toStringAsFixed(2)}%';
        var text = '${category.name} $percentage';
        final measure = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          textScaler: scaler,
        )..layout();
        if (measure.width > labelWidth) {
          text = '${category.name}\n$percentage';
          measure.text = TextSpan(text: text, style: style);
        }
        measure.layout(maxWidth: labelWidth);
        labels.add(_RingLabel(i, middle, text, measure.height));
        measure.dispose();
        angle += sweep;
      }
      final left = labels.where((l) => math.cos(l.angle) < 0).toList();
      final right = labels.where((l) => math.cos(l.angle) >= 0).toList();
      double needed(List<_RingLabel> side) =>
          side.fold<double>(0, (sum, l) => sum + l.height + 8);
      final height = math.max(
        radius * 2 + 32,
        math.max(needed(left), needed(right)) + 16,
      );
      final center = Offset(width / 2, height / 2);
      for (final side in [left, right]) {
        side.sort((a, b) => math.sin(a.angle).compareTo(math.sin(b.angle)));
        var next = 8.0;
        for (final label in side) {
          final ideal =
              center.dy +
              math.sin(label.angle) * (radius + 12) -
              label.height / 2;
          label.top = math.max(
            next,
            ideal.clamp(8.0, height - label.height - 8),
          );
          next = label.top + label.height + 8;
        }
        var bottom = height - 8;
        for (final label in side.reversed) {
          label.top = math.min(label.top, bottom - label.height);
          bottom = label.top - 8;
        }
      }
      final holeWidth = radius * 1.4;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          key: const ValueKey('category-ring-chart'),
          width: width,
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTapUp: onSelected == null
                      ? null
                      : (event) {
                          final delta = event.localPosition - center;
                          if (delta.distance < radius * .72 ||
                              delta.distance > radius) {
                            return;
                          }
                          final tappedAngle =
                              (math.atan2(delta.dy, delta.dx) + math.pi * 2) %
                              (math.pi * 2);
                          var end = 0.0;
                          for (var i = 0; i < categories.length; i++) {
                            end += categories[i].amount / total * math.pi * 2;
                            if (tappedAngle < end) {
                              onSelected!(i);
                              return;
                            }
                          }
                        },
                  child: CustomPaint(
                    painter: _CategoryRingPainter(
                      categories,
                      colors,
                      total,
                      center,
                      radius,
                      labels,
                      labelWidth,
                      theme.colorScheme.outlineVariant,
                      theme.colorScheme.surfaceContainerLow,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: center.dx - holeWidth / 2,
                top: center.dy - scaler.scale(32),
                width: holeWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      categories.first.kind == 'income' ? '总收入' : '总支出',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      amount,
                      style: amountStyle,
                      textAlign: TextAlign.center,
                    ),
                    Text(currency, style: theme.textTheme.labelSmall),
                  ],
                ),
              ),
              for (final label in labels)
                Positioned(
                  left: math.cos(label.angle) < 0 ? 0 : width - labelWidth,
                  top: label.top,
                  width: labelWidth,
                  child: Semantics(
                    label:
                        '${categories[label.index].name}，${(categories[label.index].amount / total * 100).toStringAsFixed(2)}%，$currency ${decimalMoney(categories[label.index].amount, currency)}',
                    excludeSemantics: true,
                    child: InkWell(
                      onTap: onSelected == null
                          ? null
                          : () => onSelected!(label.index),
                      child: Text(
                        label.text,
                        style: style,
                        textAlign: math.cos(label.angle) < 0
                            ? TextAlign.right
                            : TextAlign.left,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _RingLabel {
  _RingLabel(this.index, this.angle, this.text, this.height);
  final int index;
  final double angle, height;
  final String text;
  double top = 0;
}

class _CategoryRingPainter extends CustomPainter {
  _CategoryRingPainter(
    this.categories,
    this.colors,
    this.total,
    this.center,
    this.radius,
    this.labels,
    this.labelWidth,
    this.lineColor,
    this.surface,
  );
  final List<CategoryComparison> categories;
  final List<Color> colors;
  final int total;
  final Offset center;
  final double radius, labelWidth;
  final List<_RingLabel> labels;
  final Color lineColor, surface;

  @override
  void paint(Canvas canvas, Size size) {
    final thickness = radius * .28;
    final rect = Rect.fromCircle(
      center: center,
      radius: radius - thickness / 2,
    );
    var start = 0.0;
    for (var i = 0; i < categories.length; i++) {
      final sweep = categories[i].amount / total * math.pi * 2;
      final gap = categories.length == 1 ? 0.0 : math.min(.035, sweep * .2);
      canvas.drawArc(
        rect,
        start + gap / 2,
        sweep - gap,
        false,
        Paint()
          ..color = colors[i]
          ..style = PaintingStyle.stroke
          ..strokeWidth = thickness,
      );
      final innerBand = thickness * .22;
      canvas.drawArc(
        Rect.fromCircle(
          center: center,
          radius: radius - thickness + innerBand / 2,
        ),
        start + gap / 2,
        sweep - gap,
        false,
        Paint()
          ..color = Color.lerp(colors[i], surface, .4)!
          ..style = PaintingStyle.stroke
          ..strokeWidth = innerBand,
      );
      start += sweep;
    }
    final leader = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final label in labels) {
      final right = math.cos(label.angle) >= 0;
      final anchor =
          center +
          Offset(math.cos(label.angle), math.sin(label.angle)) * (radius - 4);
      final elbowX = center.dx + math.cos(label.angle) * (radius + 7);
      final y = label.top + label.height / 2;
      final endX = right ? size.width - labelWidth - 4 : labelWidth + 4;
      canvas.drawPath(
        Path()
          ..moveTo(anchor.dx, anchor.dy)
          ..lineTo(elbowX, y)
          ..lineTo(endX, y),
        leader,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CategoryRingPainter oldDelegate) => true;
}
