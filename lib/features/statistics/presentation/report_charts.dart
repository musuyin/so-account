import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/money/money.dart';
import '../data/statistics_repository.dart';

Color incomeColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF81C995)
    : const Color(0xFF237A43);
Color expenseColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFF28B82)
    : const Color(0xFFB3261E);

class FlowBars extends StatelessWidget {
  const FlowBars({super.key, required this.points, required this.currency});
  final List<ReportPoint> points;
  final String currency;
  @override
  Widget build(BuildContext context) {
    final maxAmount = points.fold<int>(
      1,
      (s, p) => math.max(s, math.max(p.income, p.expense)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          children: [
            Text('● 收入', style: TextStyle(color: incomeColor(context))),
            Text('● 支出', style: TextStyle(color: expenseColor(context))),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = math.max(constraints.maxWidth, points.length * 30.0);
            final unit = width / math.max(1, points.length);
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                height: 214,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < points.length; i++)
                      SizedBox(
                        width: unit,
                        child: Tooltip(
                          message:
                              '${points[i].label}\n收入 ${decimalMoney(points[i].income, currency)}\n支出 ${decimalMoney(points[i].expense, currency)}',
                          child: Semantics(
                            label:
                                '${points[i].label} 收入 ${points[i].income} 支出 ${points[i].expense}',
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                SizedBox(
                                  height: 160,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Container(
                                        width: math.min(10, unit / 4),
                                        height: points[i].income == 0
                                            ? 1
                                            : math.max(
                                                2,
                                                160 *
                                                    points[i].income /
                                                    maxAmount,
                                              ),
                                        decoration: BoxDecoration(
                                          color: incomeColor(context),
                                          borderRadius:
                                              const BorderRadius.vertical(
                                                top: Radius.circular(3),
                                              ),
                                        ),
                                      ),
                                      const SizedBox(width: 3),
                                      Container(
                                        width: math.min(10, unit / 4),
                                        height: points[i].expense == 0
                                            ? 1
                                            : math.max(
                                                2,
                                                160 *
                                                    points[i].expense /
                                                    maxAmount,
                                              ),
                                        decoration: BoxDecoration(
                                          color: expenseColor(context),
                                          borderRadius:
                                              const BorderRadius.vertical(
                                                top: Radius.circular(3),
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: 38,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.topCenter,
                                    child: Text(
                                      points[i].label.length > 7
                                          ? points[i].label.substring(
                                              points.length <= 7 ? 5 : 8,
                                            )
                                          : points[i].label.substring(
                                              points[i].label.length - 2,
                                            ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall,
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        Text(
          '纵轴最高 ${decimalMoney(maxAmount, currency)} · 长按柱形查看数值',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class CategoryPie extends StatelessWidget {
  const CategoryPie({
    super.key,
    required this.categories,
    required this.currency,
  });
  final List<CategoryComparison> categories;
  final String currency;
  @override
  Widget build(BuildContext context) {
    final rows = categories.where((c) => c.amount > 0).toList();
    final total = rows.fold<int>(0, (s, c) => s + c.amount);
    if (total == 0) {
      return const Padding(padding: EdgeInsets.all(24), child: Text('暂无分类数据'));
    }
    final scheme = Theme.of(context).colorScheme;
    final colors = [
      scheme.primary,
      scheme.secondary,
      scheme.tertiary,
      scheme.primaryContainer,
      scheme.secondaryContainer,
      scheme.tertiaryContainer,
    ];
    return Column(
      children: [
        Semantics(
          label: rows
              .map(
                (r) =>
                    '${r.name} ${(r.amount / total * 100).toStringAsFixed(1)}%',
              )
              .join('，'),
          child: SizedBox(
            width: 180,
            height: 180,
            child: CustomPaint(
              painter: _PiePainter(
                rows.map((r) => r.amount / total).toList(),
                colors,
                scheme.surface,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  color: colors[i % colors.length],
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(rows[i].name)),
                Text(
                  '${decimalMoney(rows[i].amount, currency)} · ${(rows[i].amount / total * 100).toStringAsFixed(1)}%',
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PiePainter extends CustomPainter {
  _PiePainter(this.values, this.colors, this.border);
  final List<double> values;
  final List<Color> colors;
  final Color border;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] * math.pi * 2;
      canvas.drawArc(
        rect,
        start,
        sweep,
        true,
        Paint()..color = colors[i % colors.length],
      );
      canvas.drawArc(
        rect,
        start,
        sweep,
        true,
        Paint()
          ..color = border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _PiePainter old) => true;
}

class AssetLine extends StatelessWidget {
  const AssetLine({super.key, required this.points, required this.currency});
  final List<ReportPoint> points;
  final String currency;
  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const Text('暂无资产数据');
    final values = points.map((p) => p.netAssets.toDouble()).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('期末净资产 ${decimalMoney(points.last.netAssets, currency)}'),
        const SizedBox(height: 12),
        Semantics(
          label: points
              .map(
                (p) => '${p.label} 净资产 ${decimalMoney(p.netAssets, currency)}',
              )
              .join('，'),
          child: SizedBox(
            height: 160,
            width: double.infinity,
            child: CustomPaint(
              painter: _LinePainter(
                values,
                Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              points.first.label,
              style: Theme.of(context).textTheme.labelSmall,
            ),
            Text(
              points.last.label,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        Text(
          '最低 ${decimalMoney(values.reduce(math.min).toInt(), currency)} · 最高 ${decimalMoney(values.reduce(math.max).toInt(), currency)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.values, this.color);
  final List<double> values;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final min = values.reduce(math.min),
        max = values.reduce(math.max),
        span = max == min ? 1 : max - min;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? size.width / 2
          : 8 + (size.width - 16) * i / (values.length - 1);
      final y = 12 + (size.height - 24) * (1 - (values[i] - min) / span);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => true;
}
