import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/providers.dart';
import '../../../app/widgets.dart';
import '../../../data/database/app_database.dart';

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
      builder: (data) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final kind in ['expense', 'income']) ...[
            Text(
              kind == 'expense' ? '支出分类' : '收入分类',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final c in data.categories.where((c) => c.kind == kind))
              ListTile(
                title: Text(c.name),
                onTap: () => openForm(context, CategoryForm(category: c)),
                trailing: IconButton(
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
              ),
            const SizedBox(height: 24),
          ],
        ],
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
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormFrame(
    title: '收支分类',
    saving: saving,
    onSave: () async {
      setState(() => saving = true);
      final ok = await perform(
        context,
        () => ref
            .read(ledgerProvider)
            .saveCategory(name.text, kind, id: widget.category?.id),
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
      DropdownButtonFormField<String>(
        initialValue: kind,
        decoration: const InputDecoration(labelText: '类型'),
        items: const [
          DropdownMenuItem(value: 'expense', child: Text('支出')),
          DropdownMenuItem(value: 'income', child: Text('收入')),
        ],
        onChanged: widget.category == null
            ? (v) => setState(() => kind = v!)
            : null,
      ),
    ],
  );
}
