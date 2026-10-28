import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/category_reordering.dart';
import '../../../app/providers/providers.dart';
import '../../../app/widgets.dart';
import '../../ledger/presentation/category_icon_picker.dart';
import '../../ledger/presentation/category_icons.dart';

class ItemCategoriesPage extends ConsumerWidget {
  const ItemCategoriesPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      title: const Text('物品种类'),
      actions: [
        IconButton(
          tooltip: '新增物品种类',
          onPressed: () => openForm(context, const ItemCategoryForm()),
          icon: const Icon(Icons.add),
        ),
      ],
    ),
    body: DataView(
      builder: (data) => CategoryManagementList(
        description: '使用属性固定为长期使用物、消耗品；种类可自定义并多选。',
        groups: [
          CategoryManagementGroup('items', '物品种类', data.itemCategoryNames),
        ],
        onReorder: (_, names) =>
            ref.read(inventoryProvider).reorderCategories(names),
        builder: (name) => ListTile(
          leading: Icon(
            categoryIcon(name, iconId: data.itemCategoryIconId(name)),
          ),
          title: Text(name),
          onTap: () => openForm(context, ItemCategoryForm(previous: name)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '删除种类',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (await confirm(context, '删除种类？', '已有物品使用的种类不能删除。') &&
                      context.mounted) {
                    await perform(
                      context,
                      () => ref.read(inventoryProvider).deleteCategory(name),
                    );
                  }
                },
              ),
              const Icon(Icons.drag_handle, semanticLabel: '长按拖动排序'),
            ],
          ),
        ),
      ),
    ),
  );
}

class ItemCategoryForm extends ConsumerStatefulWidget {
  const ItemCategoryForm({super.key, this.previous});
  final String? previous;
  @override
  ConsumerState<ItemCategoryForm> createState() => _ItemCategoryFormState();
}

class _ItemCategoryFormState extends ConsumerState<ItemCategoryForm> {
  late final name = TextEditingController(text: widget.previous);
  String? iconId;
  bool initialized = false, saving = false;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(snapshotProvider).asData?.value;
    if (!initialized && data != null) {
      iconId = widget.previous == null
          ? 'category'
          : data.itemCategoryIconId(widget.previous!);
      initialized = true;
    }
    return FormFrame(
      title: widget.previous == null ? '新增物品种类' : '修改物品种类',
      saving: saving,
      onSave: () async {
        setState(() => saving = true);
        final ok = await perform(
          context,
          () => ref
              .read(inventoryProvider)
              .saveCategory(
                name.text,
                previous: widget.previous,
                iconId: iconId,
              ),
        );
        if (mounted && context.mounted) {
          setState(() => saving = false);
          if (ok) Navigator.pop(context);
        }
      },
      children: [
        TextField(
          controller: name,
          maxLength: 40,
          decoration: const InputDecoration(labelText: '种类名称'),
        ),
        CategoryIconField(
          value: iconId ?? defaultCategoryIconId(widget.previous ?? ''),
          onChanged: (value) => setState(() => iconId = value),
        ),
      ],
    );
  }
}
