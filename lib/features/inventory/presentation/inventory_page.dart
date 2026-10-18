import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/providers.dart';
import '../../../app/widgets.dart';
import '../../../core/money/money.dart';
import '../../../core/time/business_date.dart';
import 'item_form.dart';

class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key});
  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage> {
  String search = '', category = '';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await perform(context, () async {
        final store = await ref.read(mediaProvider.future);
        final recovered = await store.recover();
        if (recovered != null && mounted) {
          await openForm(context, ItemForm(recoveredPhoto: recovered));
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('物品与陪伴')),
    body: DataView(
      builder: (data) {
        final categories = data.items.map((i) => i.category).toSet().toList()
          ..sort();
        if (!categories.contains(category)) category = '';
        final items =
            data.items
                .where(
                  (i) =>
                      (category.isEmpty || i.category == category) &&
                      '${i.name} ${i.note}'.toLowerCase().contains(
                        search.toLowerCase(),
                      ),
                )
                .toList()
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          children: [
            Text(
              '好好使用，物有所值。',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                hintText: '搜索物品或备注',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => search = v),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('全部'),
                  selected: category.isEmpty,
                  onSelected: (_) => setState(() => category = ''),
                ),
                ...categories.map(
                  (c) => ChoiceChip(
                    label: Text(c),
                    selected: category == c,
                    onSelected: (_) => setState(() => category = c),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (items.isEmpty) const EmptyState('让物品有自己的记录', '独立登记，或从一笔支出开始。'),
            for (final item in items)
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(item.name),
                  subtitle: Text(
                    '${item.category} · ${item.price == null ? '价格未记录' : money(item.price!, item.currency)}\n${item.purchasedOn == null ? '购入日期未记录' : '陪伴 ${ownershipDays(item.purchasedOn!, DateTime.now())} 天'}${item.price != null && item.purchasedOn != null ? ' · 日均 ${item.currency} ${(item.price! / (item.currency == 'JPY' ? 1 : 100) / ownershipDays(item.purchasedOn!, DateTime.now())).toStringAsFixed(2)}' : ''}',
                  ),
                  onTap: () => openForm(context, ItemForm(item: item)),
                  trailing: IconButton(
                    tooltip: '删除物品',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (await confirm(context, '删除物品？', '会解除账目关联，原账目仍保留。') &&
                          context.mounted) {
                        await perform(
                          context,
                          () => ref.read(inventoryProvider).delete(item.id),
                        );
                      }
                    },
                  ),
                ),
              ),
          ],
        );
      },
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => openForm(context, const ItemForm()),
      icon: const Icon(Icons.add),
      label: const Text('记录物品'),
    ),
  );
}
