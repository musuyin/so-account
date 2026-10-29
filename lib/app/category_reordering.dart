import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

Future<bool> _saveOrder(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('排序保存失败，已恢复原顺序，请重试')));
    }
    return false;
  }
}

const categoryReorderHint = '长按拖动排序，自动保存';

List<String> moveCategory(List<String> order, int from, int to) {
  final result = [...order];
  result.insert(to, result.removeAt(from));
  return result;
}

Map<CustomSemanticsAction, VoidCallback> categoryMoveActions(
  List<String> order,
  String id,
  void Function(List<String>) save,
) {
  final index = order.indexOf(id);
  return {
    if (index > 0)
      const CustomSemanticsAction(label: '上移'): () =>
          save(moveCategory(order, index, index - 1)),
    if (index < order.length - 1)
      const CustomSemanticsAction(label: '下移'): () =>
          save(moveCategory(order, index, index + 1)),
  };
}

/// A regular grid with animated positions. The same IDs own selection and drag
/// identity, so previewing or canceling a drag never invokes a selection callback.
class ReorderableCategoryGrid extends StatefulWidget {
  const ReorderableCategoryGrid({
    super.key,
    required this.ids,
    required this.label,
    required this.builder,
    required this.onReorder,
    this.compact = false,
    this.enabled = true,
    this.columns,
  });
  final List<String> ids;
  final String Function(String) label;
  final Widget Function(String) builder;
  final Future<void> Function(List<String>) onReorder;
  final bool compact, enabled;
  final int? columns;
  @override
  State<ReorderableCategoryGrid> createState() =>
      _ReorderableCategoryGridState();
}

class _ReorderableCategoryGridState extends State<ReorderableCategoryGrid> {
  late List<String> order = [...widget.ids];
  List<String>? beforeDrag;
  String? dragging;
  bool saving = false;
  ScrollPosition? scrollPosition;
  double scrollSpeed = 0;
  Timer? scrollTimer;

  @override
  void didUpdateWidget(covariant ReorderableCategoryGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.ids, widget.ids)) {
      // External changes invalidate an in-flight drag rather than saving stale IDs.
      stopScroll();
      dragging = null;
      beforeDrag = null;
      order = [...widget.ids];
    }
  }

  void stopScroll() {
    scrollTimer?.cancel();
    scrollTimer = null;
    scrollSpeed = 0;
  }

  void autoScroll(Offset pointer) {
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) return;
    final box = scrollable.context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(pointer);
    scrollPosition = scrollable.position;
    scrollSpeed = local.dy < 48
        ? -9
        : local.dy > box.size.height - 48
        ? 9
        : 0;
    scrollTimer ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      final p = scrollPosition;
      if (p == null || !p.hasPixels || scrollSpeed == 0) return;
      p.jumpTo(
        (p.pixels + scrollSpeed).clamp(p.minScrollExtent, p.maxScrollExtent),
      );
    });
  }

  Future<void> persist(List<String> next) async {
    if (saving || listEquals(next, widget.ids)) return;
    setState(() {
      saving = true;
      order = [...next];
    });
    final ok = await _saveOrder(context, () => widget.onReorder(next));
    if (!mounted) return;
    setState(() {
      saving = false;
      if (!ok) order = [...widget.ids];
    });
  }

  void finish(bool accepted) {
    stopScroll();
    if (dragging == null) return;
    final next = [...order];
    setState(() {
      if (!accepted) order = beforeDrag ?? [...widget.ids];
      dragging = null;
      beforeDrag = null;
    });
    if (accepted) unawaited(persist(next));
  }

  @override
  void dispose() {
    stopScroll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          categoryReorderHint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      LayoutBuilder(
        builder: (context, constraints) {
          final scaler = MediaQuery.textScalerOf(context);
          final columns =
              widget.columns ??
              (widget.compact
                  ? (constraints.maxWidth / (scaler.scale(14) > 18 ? 130 : 100))
                        .floor()
                        .clamp(2, 5)
                  : scaler.scale(14) > 18
                  ? 3
                  : constraints.maxWidth < 340
                  ? 4
                  : 5);
          final width = constraints.maxWidth / columns;
          final style = Theme.of(context).textTheme.labelMedium!;
          var labelHeight = 0.0;
          for (final id in order) {
            final painter =
                TextPainter(
                  text: TextSpan(text: widget.label(id), style: style),
                  textDirection: Directionality.of(context),
                  textScaler: scaler,
                )..layout(
                  maxWidth: math.max(
                    1,
                    width -
                        (widget.compact
                            ? 48
                            : widget.columns != null
                            ? 4
                            : 16),
                  ),
                );
            labelHeight = math.max(labelHeight, painter.height);
          }
          final height =
              labelHeight +
              (widget.compact
                  ? 28
                  : widget.columns != null
                  ? 66
                  : 80);
          return SizedBox(
            height: (order.length / columns).ceil() * height,
            child: Stack(
              children: [
                for (final id in order)
                  AnimatedPositioned(
                    key: ValueKey('reorder-$id'),
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    left: order.indexOf(id) % columns * width,
                    top: order.indexOf(id) ~/ columns * height,
                    width: width,
                    height: height,
                    child: DragTarget<String>(
                      onWillAcceptWithDetails: (details) =>
                          dragging == details.data,
                      onMove: (details) {
                        if (dragging != details.data || id == dragging) return;
                        final from = order.indexOf(details.data),
                            to = order.indexOf(id);
                        if (from >= 0) {
                          setState(() => order = moveCategory(order, from, to));
                        }
                      },
                      onAcceptWithDetails: (_) => finish(true),
                      builder: (context, candidates, rejected) => Semantics(
                        customSemanticsActions: saving || !widget.enabled
                            ? null
                            : categoryMoveActions(order, id, persist),
                        child: LongPressDraggable<String>(
                          data: id,
                          maxSimultaneousDrags: saving || !widget.enabled
                              ? 0
                              : 1,
                          onDragStarted: () => setState(() {
                            beforeDrag = [...order];
                            dragging = id;
                          }),
                          onDragUpdate: (details) =>
                              autoScroll(details.globalPosition),
                          onDraggableCanceled: (_, _) => finish(false),
                          onDragEnd: (details) => finish(details.wasAccepted),
                          feedback: Material(
                            elevation: 8,
                            borderRadius: BorderRadius.circular(12),
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHigh,
                            child: SizedBox(
                              width: width,
                              child: IgnorePointer(child: widget.builder(id)),
                            ),
                          ),
                          childWhenDragging: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              ),
                            ),
                            child: Opacity(
                              opacity: .2,
                              child: IgnorePointer(child: widget.builder(id)),
                            ),
                          ),
                          child: widget.builder(id),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ],
  );
}

class CategoryManagementGroup {
  const CategoryManagementGroup(this.id, this.title, this.ids);
  final String id, title;
  final List<String> ids;
}

class CategoryManagementList extends StatefulWidget {
  const CategoryManagementList({
    super.key,
    required this.groups,
    required this.builder,
    required this.onReorder,
    this.description,
  });
  final List<CategoryManagementGroup> groups;
  final Widget Function(String) builder;
  final Future<void> Function(String, List<String>) onReorder;
  final String? description;
  @override
  State<CategoryManagementList> createState() => _CategoryManagementListState();
}

class _CategoryManagementListState extends State<CategoryManagementList> {
  final Map<String, List<String>> pending = {};
  Future<void> save(String group, List<String> ids) async {
    if (pending.isNotEmpty) return;
    setState(() => pending[group] = ids);
    await _saveOrder(context, () => widget.onReorder(group, ids));
    if (mounted) setState(() => pending.remove(group));
  }

  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      SliverPadding(
        padding: const EdgeInsets.all(16),
        sliver: SliverToBoxAdapter(
          child: Text([?widget.description, categoryReorderHint].join('\n')),
        ),
      ),
      for (final group in widget.groups) ...[
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          sliver: SliverToBoxAdapter(
            child: Text(
              group.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ),
        SliverReorderableList(
          key: ValueKey(group.id),
          itemCount: group.ids.length,
          proxyDecorator: (child, index, animation) => AnimatedBuilder(
            animation: animation,
            builder: (context, _) =>
                Material(elevation: 8 * animation.value, child: child),
          ),
          onReorderItem: (from, to) {
            if (from != to) {
              unawaited(save(group.id, moveCategory(group.ids, from, to)));
            }
          },
          itemBuilder: (context, index) {
            final order = pending[group.id] ?? group.ids;
            final id = order[index];
            return Semantics(
              key: ValueKey(id),
              customSemanticsActions: pending.isEmpty
                  ? categoryMoveActions(order, id, (ids) => save(group.id, ids))
                  : null,
              child: ReorderableDelayedDragStartListener(
                index: index,
                enabled: pending.isEmpty,
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: widget.builder(id),
                ),
              ),
            );
          },
        ),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ],
  );
}
