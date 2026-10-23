import 'dart:io';

import 'package:flutter/material.dart';

import '../../goals/presentation/goals_page.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/providers.dart';
import '../../../app/widgets.dart';
import '../../../core/money/money.dart';
import '../../../core/time/business_date.dart';
import '../../../data/database/app_database.dart';
import '../domain/item_cost.dart';
import '../domain/item_categories.dart';
import 'item_form.dart';

class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key});
  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage> {
  final Set<String> selectedCategories = {};
  String search = '',
      useType = '',
      status = 'all',
      currency = 'CNY',
      sort = 'recent';
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
        IconButton(
          tooltip: '心愿单',
          onPressed: () =>
              openForm(context, GoalsPage(initialCurrency: currency)),
          icon: const Icon(Icons.favorite_outline),
        ),
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
          ...configuredItemCategories(
            data.preferences
                .where((p) => p.key == 'item_categories')
                .firstOrNull
                ?.value,
          ),
          ...all.expand((i) => itemTags(i.category)),
        }.toList();
        final items =
            all
                .where(
                  (i) =>
                      (selectedCategories.isEmpty ||
                          itemTags(i.category)
                              .any(selectedCategories.contains)) &&
                      (useType.isEmpty || i.useType == useType) &&
                      (status == 'all' || i.status == status) &&
                      '${i.name} ${i.note} ${itemTags(i.category).join(' ')} ${i.unit ?? ''}'
                          .toLowerCase()
                          .contains(search.toLowerCase()),
                )
                .toList()
              ..sort(
                (a, b) => switch (sort) {
                  'name' => a.name.compareTo(b.name),
                  'price' => (b.price ?? -1).compareTo(a.price ?? -1),
                  _ => b.createdAt.compareTo(a.createdAt),
                },
              );
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
              borderOnForeground: false,
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
            ClearableSearch(
              value: search,
              hint: '搜索名称、种类或备注',
              onChanged: (value) => setState(() => search = value),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${items.length} 件物品',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                DropdownButton<String>(
                  value: sort,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 'recent', child: Text('最近添加')),
                    DropdownMenuItem(value: 'name', child: Text('按名称')),
                    DropdownMenuItem(value: 'price', child: Text('价格从高到低')),
                  ],
                  onChanged: (v) => setState(() => sort = v!),
                ),
              ],
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
                  'unused': '未使用',
                  'completed': '使用完',
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
                      child: FilterChip(
                        label: Text(c.isEmpty ? '全部种类' : c),
                        selected: c.isEmpty
                            ? selectedCategories.isEmpty
                            : selectedCategories.contains(c),
                        onSelected: (selected) => setState(() {
                          if (c.isEmpty) {
                            selectedCategories.clear();
                          } else if (selected) {
                            selectedCategories.add(c);
                          } else {
                            selectedCategories.remove(c);
                          }
                        }),
                      ),
                    ),
                ],
              ),
            ),
            if (items.isEmpty) ...[
              EmptyState(
                all.isEmpty ? '暂无物品' : '没有匹配的物品',
                all.isEmpty ? '点击“记录物品”添加。' : '可清除筛选，查看其他物品。',
              ),
              if (all.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() {
                    search = '';
                    useType = '';
                    status = 'all';
                    selectedCategories.clear();
                  }),
                  child: const Text('清除筛选'),
                ),
            ],
            for (final item in items)
              Card(
                borderOnForeground: false,
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12),
                  leading: ItemThumbnail(item: item),
                  title: Text(item.name),
                  subtitle: Text(
                    '${itemTags(item.category).join('、')} · ${item.useType == 'durable' ? '长期使用物' : '消耗品'} · ${itemStatuses[item.status]}${item.quantity == null ? '' : ' · ${item.quantity}${item.unit ?? ''}'}\n${item.price == null ? '价格未记录' : money(item.price!, currency)}${dailyCost(item.price, item.purchasedOn, item.archivedOn, DateTime.now()) == null ? '' : ' · 日均 ${(dailyCost(item.price, item.purchasedOn, item.archivedOn, DateTime.now())! / factor).toStringAsFixed(2)}'}',
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
                                    : 'completed',
                                quantity: item.quantity,
                                unit: item.unit,
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
                        value: item.status != 'completed'
                            ? 'archive'
                            : 'restore',
                        child: Text(
                          item.status != 'completed' ? '使用完' : '恢复使用',
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
