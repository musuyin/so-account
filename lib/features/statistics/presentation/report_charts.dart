import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_typography.dart';
import '../../../app/widgets.dart';
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

String _axisLabel(String label) =>
    label.length == 10 || label.length == 7 ? label.substring(5) : label;

enum FlowMetric { compare, expense, income, surplus }

class FlowBars extends StatefulWidget {
  const FlowBars({
    super.key,
    required this.points,
    required this.currency,
    this.line = false,
    this.metric = FlowMetric.compare,
    this.onRecords,
  });
  final List<ReportPoint> points;
  final String currency;
  final bool line;
  final FlowMetric metric;
  final ValueChanged<ReportPoint>? onRecords;
  @override
  State<FlowBars> createState() => _FlowBarsState();
}

class _FlowBarsState extends State<FlowBars> {
  int? selected;
  @override
  void didUpdateWidget(covariant FlowBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.points != widget.points) selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    if (points.isEmpty) return const Text('暂无收支数据');
    final series = switch (widget.metric) {
      FlowMetric.compare => [
        points.map((p) => p.income).toList(),
        points.map((p) => p.expense).toList(),
      ],
      FlowMetric.income => [points.map((p) => p.income).toList()],
      FlowMetric.expense => [points.map((p) => p.expense).toList()],
      FlowMetric.surplus => [points.map((p) => p.income - p.expense).toList()],
    };
    final colors = switch (widget.metric) {
      FlowMetric.compare => [incomeColor(context), expenseColor(context)],
      FlowMetric.income => [incomeColor(context)],
      FlowMetric.expense => [expenseColor(context)],
      FlowMetric.surplus => [Theme.of(context).colorScheme.primary],
    };
    final labels = switch (widget.metric) {
      FlowMetric.compare => ['收入', '支出'],
      FlowMetric.income => ['收入'],
      FlowMetric.expense => ['支出'],
      FlowMetric.surplus => ['结余'],
    };
    final values = series.expand((s) => s);
    final minValue = values.fold<int>(0, math.min);
    final maxValue = values.fold<int>(1, math.max);
    final point = selected == null ? null : points[selected!];
    String detail(ReportPoint p) =>
        '${p.label} · ${widget.currency}\n收入 ${decimalMoney(p.income, widget.currency)} · 支出 ${decimalMoney(p.expense, widget.currency)} · 结余 ${decimalMoney(p.income - p.expense, widget.currency)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          children: [
            for (var i = 0; i < labels.length; i++)
              Text('● ${labels[i]}', style: TextStyle(color: colors[i])),
          ],
        ),
        ParameterText(
          '${widget.currency} · ${decimalMoney(minValue, widget.currency)} ～ ${decimalMoney(maxValue, widget.currency)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = math.max(
              constraints.maxWidth,
              points.length > 36 ? points.length * 14.0 : 0.0,
            );
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                child: Column(
                  children: [
                    Semantics(
                      label: '收支${widget.line ? '折线图' : '柱状图'}，可展开数据列表逐项查看',
                      child: GestureDetector(
                        key: const ValueKey('flow-chart'),
                        onTapUp: (event) => setState(
                          () => selected =
                              (event.localPosition.dx / width * points.length)
                                  .floor()
                                  .clamp(0, points.length - 1),
                        ),
                        child: CustomPaint(
                          size: Size(width, 160),
                          painter: _FlowPainter(
                            series,
                            colors,
                            minValue,
                            maxValue,
                            widget.line,
                            Theme.of(context).colorScheme.outlineVariant,
                            selected,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _axisLabel(points.first.label),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        if (points.length > 1)
                          Text(
                            _axisLabel(points.last.label),
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        Text('零基线，点击图形查看数值', style: Theme.of(context).textTheme.bodySmall),
        if (point != null) ...[
          ParameterText(detail(point)),
          if (widget.onRecords != null)
            TextButton(
              onPressed: () => widget.onRecords!(point),
              child: const Text('查看记录'),
            ),
        ],
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('数据列表'),
          children: [
            for (final point in points)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: ParameterText(detail(point)),
                onTap: widget.onRecords == null
                    ? null
                    : () => widget.onRecords!(point),
                trailing: widget.onRecords == null
                    ? null
                    : const Icon(Icons.chevron_right),
              ),
          ],
        ),
      ],
    );
  }
}

class _FlowPainter extends CustomPainter {
  _FlowPainter(
    this.series,
    this.colors,
    this.minimum,
    this.maximum,
    this.line,
    this.axis,
    this.selected,
  );
  final List<List<int>> series;
  final List<Color> colors;
  final int minimum, maximum;
  final bool line;
  final Color axis;
  final int? selected;
  @override
  void paint(Canvas canvas, Size size) {
    final n = series.first.length, unit = size.width / series.first.length;
    double y(int v) =>
        8 + (size.height - 16) * (maximum - v) / (maximum - minimum);
    final zero = y(0);
    canvas.drawLine(
      Offset(0, zero),
      Offset(size.width, zero),
      Paint()
        ..color = axis
        ..strokeWidth = 1,
    );
    for (var s = 0; s < series.length; s++) {
      final paint = Paint()
        ..color = colors[s]
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final path = Path();
      for (var i = 0; i < n; i++) {
        final x = unit * (i + .5), valueY = y(series[s][i]);
        if (line) {
          if (i == 0) {
            path.moveTo(x, valueY);
          } else {
            path.lineTo(x, valueY);
          }
          canvas.drawCircle(
            Offset(x, valueY),
            selected == i ? 5 : 2.5,
            Paint()..color = colors[s],
          );
        } else if (series[s][i] != 0) {
          final w = math.min(18.0, unit / (series.length + 2));
          final left = x + (s - series.length / 2) * w;
          canvas.drawRect(
            Rect.fromLTRB(
              left,
              math.min(zero, valueY),
              left + w - 2,
              math.max(zero, valueY),
            ),
            Paint()..color = colors[s],
          );
        }
      }
      if (line) canvas.drawPath(path, paint);
    }
    if (selected != null) {
      final x = unit * (selected! + .5);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = axis
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FlowPainter old) => true;
}

Color categoryColor(String id, Brightness brightness) {
  var hash = 0;
  for (final c in id.runes) {
    hash = (hash * 31 + c) % 360;
  }
  return HSLColor.fromAHSL(
    1,
    (hash * 137.508) % 360,
    .55,
    brightness == Brightness.dark ? .68 : .40,
  ).toColor();
}

class CategoryPie extends StatefulWidget {
  const CategoryPie({
    super.key,
    required this.categories,
    required this.currency,
    this.bars = false,
    this.onRecords,
  });
  final List<CategoryComparison> categories;
  final String currency;
  final bool bars;
  final ValueChanged<CategoryComparison>? onRecords;
  @override
  State<CategoryPie> createState() => _CategoryPieState();
}

class _CategoryPieState extends State<CategoryPie> {
  bool expanded = false;
  @override
  Widget build(BuildContext context) {
    final all = widget.categories.where((c) => c.amount > 0).toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    final total = all.fold<int>(0, (s, c) => s + c.amount);
    if (total == 0) {
      return const Padding(padding: EdgeInsets.all(16), child: Text('暂无分类数据'));
    }
    final rows = expanded || all.length <= 5
        ? all
        : [
            ...all.take(5),
            CategoryComparison(
              '__other__',
              '其他',
              all.first.kind,
              all.skip(5).fold<int>(0, (s, c) => s + c.amount),
              0,
            ),
          ];
    final colors = [
      for (final c in rows) categoryColor(c.id, Theme.of(context).brightness),
    ];
    return Column(
      children: [
        if (!widget.bars)
          SizedBox(
            width: double.infinity,
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _RingPainter(
                        rows.map((r) => r.amount / total).toList(),
                        colors,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.currency,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          decimalMoney(total, widget.currency),
                          style: AppTypography.amount.copyWith(fontSize: 24),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        for (var i = 0; i < rows.length; i++)
          InkWell(
            onTap: rows[i].id == '__other__'
                ? () => setState(() => expanded = true)
                : widget.onRecords == null
                ? null
                : () => widget.onRecords!(rows[i]),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: Icon(
                                Icons.circle,
                                size: 10,
                                color: colors[i],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(child: Text(rows[i].name)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          decimalMoney(rows[i].amount, widget.currency),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${(rows[i].amount / total * 100).toStringAsFixed(1)}%',
                          textAlign: TextAlign.right,
                        ),
                      ),
                      if (widget.onRecords != null)
                        const Icon(Icons.chevron_right, size: 16),
                    ],
                  ),
                  if (widget.bars)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: LinearProgressIndicator(
                        value: rows[i].amount / all.first.amount,
                        color: colors[i],
                        minHeight: 8,
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (all.length > 5)
          TextButton(
            onPressed: () => setState(() => expanded = !expanded),
            child: Text(expanded ? '收起分类' : '展开全部分类'),
          ),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.values, this.colors);
  final List<double> values;
  final List<Color> colors;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(15);
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] * math.pi * 2;
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..color = colors[i]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 24,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => true;
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
        ParameterText(
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
