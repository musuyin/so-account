import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/providers/providers.dart';
import '../../../app/widgets.dart';
import '../../../core/money/money.dart';
import '../../../core/time/business_date.dart';
import '../../../data/database/app_database.dart';
import '../../ledger/presentation/entry_form.dart';
import '../domain/item_cost.dart';
import '../domain/item_categories.dart';

class ItemForm extends ConsumerStatefulWidget {
  const ItemForm({
    super.key,
    this.item,
    this.initialEntry,
    this.recoveredPhoto,
    this.initialCurrency = 'CNY',
  });
  final Item? item;
  final Entry? initialEntry;
  final String? recoveredPhoto;
  final String initialCurrency;
  @override
  ConsumerState<ItemForm> createState() => _ItemFormState();
}

class _ItemFormState extends ConsumerState<ItemForm> {
  late final name = TextEditingController(text: widget.item?.name);
  late final Set<String> categories = itemTags(widget.item?.category ?? '')
      .toSet();
  late final quantity = TextEditingController(text: widget.item?.quantity);
  late final unit = TextEditingController(text: widget.item?.unit);
  late final note = TextEditingController(text: widget.item?.note);
  final price = TextEditingController();
  late String? date = widget.item?.purchasedOn ?? widget.initialEntry?.date;
  String currency = 'CNY';
  late String? photo = widget.item?.photo ?? widget.recoveredPhoto;
  late String useType = widget.item?.useType ?? 'durable';
  late String status = widget.item?.status ?? 'active';
  late String? archivedOn = widget.item?.archivedOn;
  final Set<String> links = {};
  bool initialized = false, saving = false;
  @override
  void dispose() {
    name.dispose();
    quantity.dispose();
    unit.dispose();
    note.dispose();
    price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DataView(
    builder: (data) {
      if (!initialized) {
        currency =
            widget.item?.currency ??
            (widget.initialEntry == null
                ? widget.initialCurrency
                : data.account(widget.initialEntry!.accountId).currency);
        if (widget.item?.price != null) {
          price.text = decimalMoney(widget.item!.price!, currency);
        }
        if (widget.item != null) {
          links.addAll(
            data.links
                .where((l) => l.itemId == widget.item!.id)
                .map((l) => l.entryId),
          );
        }
        if (widget.initialEntry != null) links.add(widget.initialEntry!.id);
        initialized = true;
      }
      final expenses =
          data.entries
              .where(
                (e) =>
                    e.kind == 'expense' &&
                    data.account(e.accountId).currency == currency,
              )
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date));
      return FormFrame(
        title: widget.item == null ? '记录一件物品' : '物品详情与编辑',
        saving: saving,
        onSave: () async {
          setState(() => saving = true);
          final ok = await perform(context, () async {
            await ref
                .read(inventoryProvider)
                .save(
                  id: widget.item?.id,
                  name: name.text,
                  category: encodeItemTags(categories),
                  currency: currency,
                  price: price.text.trim().isEmpty
                      ? null
                      : parseMoney(price.text, currency),
                  purchasedOn: date,
                  note: note.text,
                  photo: photo,
                  useType: useType,
                  status: status,
                  archivedOn: archivedOn,
                  quantity: useType == 'consumable' ? quantity.text : null,
                  unit: useType == 'consumable' ? unit.text : null,
                  entryIds: links.toList(),
                );
          });
          if (mounted && context.mounted) {
            setState(() => saving = false);
            if (ok) Navigator.pop(context);
          }
        },
        children: [
          TextField(
            controller: name,
            maxLength: 100,
            decoration: const InputDecoration(labelText: '物品名称'),
          ),
          const Text('物品种类 · 可多选'),
          Wrap(
            spacing: 6,
            children: [
              for (final c in {
                ...configuredItemCategories(
                  data.preferences
                      .where((p) => p.key == 'item_categories')
                      .firstOrNull
                      ?.value,
                ),
                ...categories,
              })
                FilterChip(
                  label: Text(c),
                  selected: categories.contains(c),
                  onSelected: (selected) => setState(() {
                    if (selected) {
                      categories.add(c);
                    } else {
                      categories.remove(c);
                    }
                  }),
                ),
            ],
          ),
          DropdownButtonFormField<String>(
            initialValue: useType,
            decoration: const InputDecoration(labelText: '使用属性'),
            items: const [
              DropdownMenuItem(value: 'durable', child: Text('长期使用物')),
              DropdownMenuItem(value: 'consumable', child: Text('消耗品')),
            ],
            onChanged: (v) => setState(() {
              useType = v!;
            }),
          ),
          if (useType == 'consumable') ...[
            TextField(
              controller: quantity,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: '数量 / 容量 · 可留空',
                hintText: '例如：500',
              ),
            ),
            TextField(
              controller: unit,
              maxLength: 20,
              decoration: const InputDecoration(
                labelText: '单位 · 可留空',
                hintText: '例如：ml、g、包、个',
              ),
            ),
          ],
          DropdownButtonFormField<String>(
            key: ValueKey('status-$useType-$status'),
            initialValue: status,
            decoration: const InputDecoration(labelText: '使用状态'),
            items: [
              for (final entry in itemStatuses.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (v) => setState(() {
              status = v!;
              archivedOn = status == 'completed'
                  ? dateKey(DateTime.now())
                  : null;
            }),
          ),
          if (status == 'completed')
            ListTile(
              title: const Text('使用完日期'),
              subtitle: Text(archivedOn ?? ''),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final value = await showDatePicker(
                  context: context,
                  initialDate: parseDate(archivedOn!),
                  firstDate: DateTime(1900),
                  lastDate: DateTime.now(),
                );
                if (value != null) setState(() => archivedOn = dateKey(value));
              },
            ),
          DropdownButtonFormField<String>(
            initialValue: currency,
            decoration: const InputDecoration(labelText: '币种'),
            items: currencies
                .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                .toList(),
            onChanged: (v) => setState(() {
              currency = v!;
              links.clear();
            }),
          ),
          TextField(
            controller: price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '购入价格 · 可留空',
              helperText: '填写这件物品自己的价格；关联账目不会自动分摊或覆盖价格。',
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('购入日期'),
            subtitle: Text(date ?? '未记录'),
            trailing: date == null
                ? const Icon(Icons.calendar_today)
                : IconButton(
                    tooltip: '清除日期',
                    onPressed: () => setState(() => date = null),
                    icon: const Icon(Icons.clear),
                  ),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: date == null ? DateTime.now() : parseDate(date!),
                firstDate: DateTime(1900),
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => date = dateKey(picked));
            },
          ),
          if (widget.item?.price != null && widget.item?.purchasedOn != null)
            Text(
              '记录日均 $currency ${(dailyCost(widget.item!.price, widget.item!.purchasedOn, widget.item!.archivedOn, DateTime.now())! / (currency == 'JPY' ? 1 : 100)).toStringAsFixed(2)}${widget.item!.archivedOn == null ? '' : ' · 截止归档日'}',
            ),
          if (photo != null)
            ref
                .watch(mediaProvider)
                .when(
                  data: (store) => ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.file(
                      File(store.resolve(photo!).path),
                      height: 220,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Text('图片暂不可用'),
                    ),
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => const Text('无法打开图片'),
                ),
          Wrap(
            spacing: 8,
            children: [
              for (final source in ImageSource.values)
                OutlinedButton.icon(
                  onPressed: () async {
                    await perform(context, () async {
                      final store = await ref.read(mediaProvider.future);
                      final result = await store.pick(source);
                      if (result != null && mounted) {
                        setState(() => photo = result);
                      }
                    });
                  },
                  icon: Icon(
                    source == ImageSource.camera
                        ? Icons.camera_alt_outlined
                        : Icons.photo_outlined,
                  ),
                  label: Text(source == ImageSource.camera ? '拍照' : '选择照片'),
                ),
              if (photo != null)
                TextButton(
                  onPressed: () => setState(() => photo = null),
                  child: const Text('移除照片'),
                ),
            ],
          ),
          TextField(
            controller: note,
            maxLength: 2000,
            maxLines: 3,
            decoration: const InputDecoration(labelText: '备注'),
          ),
          Text('关联购买支出 · 可多选', style: Theme.of(context).textTheme.titleMedium),
          if (expenses.isEmpty) const Text('暂无同币种支出，物品也可以独立保存。'),
          for (final entry in expenses)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: links.contains(entry.id),
              onChanged: (v) => setState(() {
                if (v!) {
                  links.add(entry.id);
                } else {
                  links.remove(entry.id);
                }
              }),
              title: Text(
                '${entry.date} · ${data.category(entry.categoryId)} · ${decimalMoney(entry.amount, currency)}',
              ),
              subtitle: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: () => openForm(context, EntryForm(entry: entry)),
                    child: const Text('查看账目'),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}
