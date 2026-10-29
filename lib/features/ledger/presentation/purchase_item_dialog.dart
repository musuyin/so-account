import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/providers.dart';
import '../../../app/category_reordering.dart';
import 'category_icons.dart';

import '../../../core/money/money.dart';
import '../../inventory/domain/new_purchase_item.dart';

/// Edits a local draft; no item is written until its expense is saved.
class PurchaseItemDialog extends ConsumerStatefulWidget {
  const PurchaseItemDialog({
    super.key,
    required this.currency,
    this.categories = const [],
    this.initial,
  });
  final String currency;
  final List<String> categories;
  final NewPurchaseItem? initial;
  @override
  ConsumerState<PurchaseItemDialog> createState() => _PurchaseItemDialogState();
}

class _PurchaseItemDialogState extends ConsumerState<PurchaseItemDialog> {
  late final name = TextEditingController(text: widget.initial?.name);
  late final price = TextEditingController(
    text: widget.initial?.price == null
        ? ''
        : decimalMoney(widget.initial!.price!, widget.currency),
  );
  late final quantity = TextEditingController(text: widget.initial?.quantity);
  late final unit = TextEditingController(text: widget.initial?.unit);
  late String? category = widget.initial?.category;
  late String useType = widget.initial?.useType ?? 'durable';
  String? error;
  @override
  void dispose() {
    name.dispose();
    price.dispose();
    quantity.dispose();
    unit.dispose();
    super.dispose();
  }

  void accept() {
    try {
      if (name.text.trim().isEmpty || name.text.trim().length > 100) {
        throw const FormatException('物品名称为 1–100 字');
      }
      if (category == null) throw const FormatException('请选择物品类型');
      final value = price.text.trim().isEmpty
          ? null
          : parseMoney(price.text, widget.currency);
      if (value != null && (value < 0 || value > 999999999999)) {
        throw const FormatException('物品价格无效');
      }
      final q = quantity.text.trim(), u = unit.text.trim();
      if (useType == 'consumable' &&
          ((q.isNotEmpty &&
                  (!RegExp(r'^\d{1,12}(\.\d{1,6})?$').hasMatch(q) ||
                      num.parse(q) <= 0)) ||
              (u.isNotEmpty && q.isEmpty) ||
              u.length > 20)) {
        throw const FormatException('数量须大于零，最多 6 位小数；填写单位前请先填写数量');
      }
      Navigator.pop(
        context,
        NewPurchaseItem(
          name: name.text.trim(),
          category: category!,
          useType: useType,
          price: value,
          quantity: useType == 'consumable' ? q : null,
          unit: useType == 'consumable' ? u : null,
        ),
      );
    } on FormatException catch (e) {
      setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(snapshotProvider);
    final data = snapshot.asData?.value;
    final values = {
      ...?data?.itemCategoryNames,
      if (data == null) ...widget.categories,
      ?category,
      '未分类',
    }.toList();
    return AlertDialog(
      title: const Text('记物'),

      content: SizedBox(
        width: 480,
        height: MediaQuery.sizeOf(context).height * .58,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: '物品名称',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              const Text('物品类型'),
              if (snapshot.hasError) const Text('种类读取失败，请重新打开'),
              ReorderableCategoryGrid(
                compact: true,
                ids: values,
                label: (id) => id,
                enabled: data != null,
                onReorder: (ids) =>
                    ref.read(inventoryProvider).reorderCategories(ids),
                builder: (value) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: ChoiceChip(
                    showCheckmark: false,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.all(4),
                    avatar: Icon(
                      categoryIcon(
                        value,
                        iconId: data?.itemCategoryIconId(value),
                      ),
                      size: 18,
                    ),
                    label: Text(
                      value,
                      softWrap: true,
                      maxLines: 40,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    selected: category == value,
                    onSelected: (_) => setState(() => category = value),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text('使用属性'),
              Wrap(
                spacing: 6,
                children: [
                  for (final pair in [
                    ('durable', '长期使用物'),
                    ('consumable', '消耗品'),
                  ])
                    ChoiceChip(
                      label: Text(pair.$2),
                      selected: useType == pair.$1,
                      onSelected: (_) => setState(() => useType = pair.$1),
                    ),
                ],
              ),
              if (useType == 'consumable') ...[
                TextField(
                  controller: quantity,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: '数量 / 容量（可留空）'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: unit,
                  maxLength: 20,
                  decoration: const InputDecoration(
                    labelText: '单位（可留空）',
                    counterText: '',
                  ),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: price,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: '物品价格（选填）',
                  helperText: '${widget.currency} · 单独填写，不自动分配整笔支出',
                  helperMaxLines: 3,
                ),
              ),
              const SizedBox(height: 8),
              const Text('确认后暂存，保存支出时一起创建物品并关联；购入日期与支出一致。'),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: accept, child: const Text('确认记物')),
      ],
    );
  }
}
