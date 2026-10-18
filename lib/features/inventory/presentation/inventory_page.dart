import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/providers.dart';
import '../../../app/widgets.dart';
import '../../../core/money/money.dart';
import '../../../core/time/business_date.dart';
import '../../../data/database/app_database.dart';
import '../domain/item_cost.dart';
import 'item_form.dart';

class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key});
  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage> {
  String search = '',
      category = '',
      useType = '',
      status = 'active',
      currency = 'CNY';
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
    appBar: AppBar(
      title: const Text('物品'),
      actions: [
        DropdownButton(
          value: currency,
          items: currencies
              .map((v) => DropdownMenuItem(value: v, child: Text(v)))
              .toList(),
          onChanged: (v) => setState(() => currency = v!),
        ),
      ],
    ),
    body: DataView(
      builder: (data) {
        final all = data.items.where((i) => i.currency == currency).toList();
        final categories = {
          ...itemCategories,
          ...all.map((i) => i.category),
        }.toList();
        final items =
            all
                .where(
                  (i) =>
                      (category.isEmpty || i.category == category) &&
                      (useType.isEmpty || i.useType == useType) &&
                      (status == 'all' ||
                          (status == 'active'
                              ? i.status == 'active'
                              : i.status != 'active')) &&
                      '${i.name} ${i.note}'.toLowerCase().contains(
                        search.toLowerCase(),
                      ),
                )
                .toList()
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        final total = all.fold<int>(0, (s, i) => s + (i.price ?? 0));
        final costs = all
            .map(
              (i) => dailyCost(
                i.price,
                i.purchasedOn,
                i.archivedOn,
                DateTime.now(),
              ),
            )
            .whereType<double>()
            .toList();
        final factor = currency == 'JPY' ? 1 : 100;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('全部物品买入价'),
                    Text(
                      money(total, currency),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '日均合计 $currency ${(costs.fold<double>(0, (s, c) => s + c) / factor).toStringAsFixed(2)}',
                    ),
                    Text(
                      '${all.length} 件 · ${all.where((i) => i.price == null).length} 件价格未记录 · ${all.length - costs.length} 件未计算日均',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                hintText: '搜索物品或备注',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => search = v),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in {
                  '': '全部属性',
                  'durable': '长期使用物',
                  'consumable': '消耗品',
                }.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: useType == entry.key,
                    onSelected: (_) => setState(() => useType = entry.key),
                  ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in {
                  'active': '使用中',
                  'archived': '已归档',
                  'all': '全部状态',
                }.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: status == entry.key,
                    onSelected: (_) => setState(() => status = entry.key),
                  ),
              ],
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final c in ['', ...categories])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(c.isEmpty ? '全部种类' : c),
                        selected: category == c,
                        onSelected: (_) => setState(() => category = c),
                      ),
                    ),
                ],
              ),
            ),
            if (items.isEmpty) const EmptyState('暂无物品', '点击“记录物品”添加。'),
            for (final item in items)
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12),
                  leading: ItemThumbnail(item: item),
                  title: Text(item.name),
                  subtitle: Text(
                    '${item.category} · ${item.useType == 'durable' ? '长期使用物' : '消耗品'} · ${item.status == 'active'
                        ? '使用中'
                        : item.status == 'retired'
                        ? '已报废'
                        : '已用罄'}\n${item.price == null ? '价格未记录' : money(item.price!, currency)}${dailyCost(item.price, item.purchasedOn, item.archivedOn, DateTime.now()) == null ? '' : ' · 日均 ${(dailyCost(item.price, item.purchasedOn, item.archivedOn, DateTime.now())! / factor).toStringAsFixed(2)}'}',
                  ),
                  onTap: () => openForm(context, ItemForm(item: item)),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) async {
                      if (action == 'delete') {
                        if (await confirm(context, '删除物品？', '账目会保留，购买关联将解除。') &&
                            context.mounted) {
                          await perform(
                            context,
                            () => ref.read(inventoryProvider).delete(item.id),
                          );
                        }
                      } else {
                        await perform(context, () async {
                          await ref
                              .read(inventoryProvider)
                              .save(
                                id: item.id,
                                name: item.name,
                                category: item.category,
                                currency: item.currency,
                                price: item.price,
                                purchasedOn: item.purchasedOn,
                                note: item.note,
                                photo: item.photo,
                                useType: item.useType,
                                status: action == 'restore'
                                    ? 'active'
                                    : item.useType == 'durable'
                                    ? 'retired'
                                    : 'depleted',
                                archivedOn: action == 'restore'
                                    ? null
                                    : dateKey(DateTime.now()),
                                entryIds: data.links
                                    .where((l) => l.itemId == item.id)
                                    .map((l) => l.entryId)
                                    .toList(),
                              );
                        });
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: item.status == 'active' ? 'archive' : 'restore',
                        child: Text(
                          item.status == 'active'
                              ? (item.useType == 'durable' ? '报废归档' : '用罄归档')
                              : '恢复使用',
                        ),
                      ),
                      const PopupMenuItem(value: 'delete', child: Text('删除物品')),
                    ],
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

class ItemThumbnail extends ConsumerWidget {
  const ItemThumbnail({super.key, required this.item});
  final Item item;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (item.photo == null) {
      return const CircleAvatar(child: Icon(Icons.inventory_2_outlined));
    }
    return ref
        .watch(mediaProvider)
        .when(
          data: (store) => ClipOval(
            child: Image.file(
              File(store.resolve(item.photo!).path),
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  const CircleAvatar(child: Icon(Icons.broken_image_outlined)),
            ),
          ),
          loading: () => const CircleAvatar(child: Icon(Icons.photo_outlined)),
          error: (_, _) =>
              const CircleAvatar(child: Icon(Icons.broken_image_outlined)),
        );
  }
}
