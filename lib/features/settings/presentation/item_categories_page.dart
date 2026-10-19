import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/providers.dart';
import '../../../app/widgets.dart';
import '../../inventory/domain/item_categories.dart';

class ItemCategoriesPage extends ConsumerWidget {
  const ItemCategoriesPage({super.key});
  Future<void> edit(
    BuildContext context,
    WidgetRef ref, [
    String? previous,
  ]) async {
    final input = TextEditingController(text: previous);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(previous == null ? '新增物品种类' : '修改物品种类'),
        content: TextField(
          controller: input,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(labelText: '种类名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    // Dialog widgets retain their controller until the closing animation ends.
    if (name != null && context.mounted) {
      await perform(
        context,
        () =>
            ref.read(inventoryProvider).saveCategory(name, previous: previous),
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    input.dispose();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      title: const Text('物品种类'),
      actions: [
        IconButton(
          tooltip: '新增物品种类',
          onPressed: () => edit(context, ref),
          icon: const Icon(Icons.add),
        ),
      ],
    ),
    body: DataView(
      builder: (data) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('使用属性固定为长期使用物、消耗品；种类可自定义并多选。'),
          for (final category in configuredItemCategories(
            data.preferences
                .where((p) => p.key == 'item_categories')
                .firstOrNull
                ?.value,
          ))
            ListTile(
              title: Text(category),
              onTap: () => edit(context, ref, category),
              trailing: IconButton(
                tooltip: '删除种类',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (await confirm(context, '删除种类？', '已有物品使用的种类不能删除。') &&
                      context.mounted) {
                    await perform(
                      context,
                      () =>
                          ref.read(inventoryProvider).deleteCategory(category),
                    );
                  }
                },
              ),
            ),
        ],
      ),
    ),
  );
}
