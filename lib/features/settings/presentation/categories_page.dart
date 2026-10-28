import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/category_reordering.dart';
import '../../../app/providers/providers.dart';
import '../../../app/widgets.dart';
import '../../../data/database/app_database.dart';
import '../../ledger/presentation/category_icon_picker.dart';
import '../../ledger/presentation/category_icons.dart';

class CategoriesPage extends ConsumerWidget {
  const CategoriesPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      title: const Text('收支分类'),
      actions: [
        IconButton(
          tooltip: '新增分类',
          onPressed: () => openForm(context, const CategoryForm()),
          icon: const Icon(Icons.add),
        ),
      ],
    ),
    body: DataView(
      builder: (data) => CategoryManagementList(
        groups: [
          for (final kind in ['expense', 'income'])
            CategoryManagementGroup(
              kind,
              kind == 'expense' ? '支出分类' : '收入分类',
              data.categories
                  .where((c) => c.kind == kind)
                  .map((c) => c.id)
                  .toList(),
            ),
        ],
        onReorder: (kind, ids) =>
            ref.read(ledgerProvider).reorderCategories(kind, ids),
        builder: (id) {
          final c = data.categories.firstWhere((c) => c.id == id);
          return ListTile(
            leading: Icon(
              categoryIcon(c.name, iconId: data.categoryIconId(c.id)),
            ),
            title: Text(c.name),
            onTap: () => openForm(context, CategoryForm(category: c)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '删除分类',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    if (await confirm(context, '删除分类？', '已使用的分类不能删除。') &&
                        context.mounted) {
                      await perform(
                        context,
                        () => ref.read(ledgerProvider).deleteCategory(c.id),
                      );
                    }
                  },
                ),
                const Icon(Icons.drag_handle, semanticLabel: '长按拖动排序'),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class CategoryForm extends ConsumerStatefulWidget {
  const CategoryForm({super.key, this.category});
  final Category? category;
  @override
  ConsumerState<CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends ConsumerState<CategoryForm> {
  late final name = TextEditingController(text: widget.category?.name);
  late String kind = widget.category?.kind ?? 'expense';
  bool saving = false;
  String? iconId;
  bool iconInitialized = false;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(snapshotProvider).asData?.value;
    if (!iconInitialized && data != null) {
      iconId = widget.category == null
          ? 'category'
          : data.categoryIconId(widget.category!.id);
      iconInitialized = true;
    }
    return FormFrame(
      title: '收支分类',
      saving: saving,
      onSave: () async {
        setState(() => saving = true);
        final ok = await perform(
          context,
          () => ref
              .read(ledgerProvider)
              .saveCategory(
                name.text,
                kind,
                id: widget.category?.id,
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
          decoration: const InputDecoration(labelText: '分类名称'),
        ),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'expense',
              label: Text('支出'),
              icon: Icon(Icons.remove),
            ),
            ButtonSegment(
              value: 'income',
              label: Text('收入'),
              icon: Icon(Icons.add),
            ),
          ],
          selected: {kind},
          onSelectionChanged: widget.category == null
              ? (values) => setState(() => kind = values.single)
              : null,
        ),
        CategoryIconField(
          value: iconId ?? defaultCategoryIconId(widget.category?.name ?? ''),
          onChanged: (value) => setState(() => iconId = value),
        ),
      ],
    );
  }
}
