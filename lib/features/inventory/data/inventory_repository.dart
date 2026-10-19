import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/money/money.dart';
import '../../../core/time/business_date.dart';
import '../../../data/database/app_database.dart';
import '../domain/item_categories.dart';

class InventoryRepository {
  InventoryRepository(this.db);
  final AppDatabase db;
  Stream<List<Item>> watchItems() => (db.select(
    db.items,
  )..orderBy([(i) => OrderingTerm.desc(i.createdAt)])).watch();
  Stream<List<PurchaseLink>> watchLinks() =>
      db.select(db.purchaseLinks).watch();

  Future<String> save({
    String? id,
    required String name,
    required String category,
    required String currency,
    int? price,
    String? purchasedOn,
    String note = '',
    String? photo,
    String useType = 'durable',
    String status = 'active',
    String? archivedOn,
    String? quantity,
    String? unit,
    List<String> entryIds = const [],
  }) => db.transaction(() async {
    if (name.trim().isEmpty || name.trim().length > 100) {
      throw const FormatException('物品名称为 1–100 字');
    }
    final tags = itemTags(category)
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList();
    if (tags.length > 100 ||
        tags.any((v) => v.length > 80) ||
        note.length > 2000) {
      throw const FormatException('分类或备注过长');
    }
    fractionDigits(currency);
    if (price != null && (price < 0 || price > 999999999999)) {
      throw const FormatException('购入价无效');
    }
    if (purchasedOn != null) ownershipDays(purchasedOn, DateTime.now());
    if (!['durable', 'consumable'].contains(useType) ||
        !itemStatuses.containsKey(status)) {
      throw const FormatException('物品属性与归档状态不匹配');
    }
    if (status != 'completed' && archivedOn != null ||
        status == 'completed' && archivedOn == null) {
      throw const FormatException('请设置有效归档日期');
    }
    quantity = quantity?.trim();
    unit = unit?.trim();
    if (quantity?.isEmpty ?? false) quantity = null;
    if (unit?.isEmpty ?? false) unit = null;
    if ((quantity != null || unit != null) && useType != 'consumable' ||
        (unit != null && quantity == null) ||
        (unit?.length ?? 0) > 20 ||
        (quantity != null &&
            (!RegExp(r'^\d{1,12}(\.\d{1,6})?$').hasMatch(quantity!) ||
                num.parse(quantity!) <= 0))) {
      throw const FormatException('消耗品数量须大于零，最多 6 位小数；单位最多 20 字');
    }
    if (archivedOn != null) {
      ownershipDays(archivedOn, DateTime.now());
      if (purchasedOn != null && archivedOn.compareTo(purchasedOn) < 0) {
        throw const FormatException('归档不能早于购入');
      }
    }
    if (photo != null &&
        !RegExp(r'^media/[a-zA-Z0-9_-]+\.(jpg|png|jpeg)$').hasMatch(photo)) {
      throw const FormatException('无效图片路径');
    }
    for (final entryId in entryIds.toSet()) {
      final entry = await (db.select(
        db.entries,
      )..where((e) => e.id.equals(entryId))).getSingleOrNull();
      if (entry == null || entry.kind != 'expense') {
        throw const FormatException('只能关联有效支出');
      }
      final account = await (db.select(
        db.accounts,
      )..where((a) => a.id.equals(entry.accountId))).getSingle();
      if (account.currency != currency) {
        throw const FormatException('关联支出与物品的币种必须一致');
      }
    }
    final itemId = id ?? const Uuid().v4();
    final old = id == null
        ? null
        : await (db.select(
            db.items,
          )..where((i) => i.id.equals(id))).getSingle();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db
        .into(db.items)
        .insertOnConflictUpdate(
          ItemsCompanion.insert(
            id: itemId,
            name: name.trim(),
            category: Value(encodeItemTags(tags.isEmpty ? ['未分类'] : tags)),
            currency: currency,
            price: Value(price),
            purchasedOn: Value(purchasedOn),
            note: Value(note.trim()),
            photo: Value(photo),
            useType: Value(useType),
            status: Value(status),
            archivedOn: Value(archivedOn),
            quantity: Value(quantity),
            unit: Value(unit),
            createdAt: old?.createdAt ?? now,
            updatedAt: now,
          ),
        );
    await (db.delete(
      db.purchaseLinks,
    )..where((l) => l.itemId.equals(itemId))).go();
    for (final entryId in entryIds.toSet()) {
      await db
          .into(db.purchaseLinks)
          .insert(
            PurchaseLinksCompanion.insert(itemId: itemId, entryId: entryId),
          );
    }
    return itemId;
  });

  Future<void> delete(String id) =>
      (db.delete(db.items)..where((i) => i.id.equals(id))).go();

  Future<void> saveCategory(String name, {String? previous}) =>
      db.transaction(() async {
        name = name.trim();
        final pref = await (db.select(
          db.preferences,
        )..where((p) => p.key.equals('item_categories'))).getSingleOrNull();
        final categories = configuredItemCategories(pref?.value);
        if (name.isEmpty ||
            name.length > 40 ||
            (name != previous && categories.contains(name))) {
          throw const FormatException('种类名称须为 1–40 字且不能重复');
        }
        if (previous == null) {
          categories.add(name);
        } else {
          if (!categories.contains(previous) &&
              (await db.select(db.items).get()).any(
                (i) => itemTags(i.category).contains(previous),
              )) {
            categories.add(previous);
          }
          final index = categories.indexOf(previous);
          if (index < 0) throw const FormatException('种类不存在');
          categories[index] = name;
          for (final item in await db.select(db.items).get()) {
            final tags = itemTags(item.category);
            if (tags.contains(previous)) {
              await (db.update(
                db.items,
              )..where((i) => i.id.equals(item.id))).write(
                ItemsCompanion(
                  category: Value(
                    encodeItemTags(tags.map((v) => v == previous ? name : v)),
                  ),
                ),
              );
            }
          }
        }
        validateItemCategories(encodeItemTags(categories));
        await db
            .into(db.preferences)
            .insertOnConflictUpdate(
              PreferencesCompanion.insert(
                key: 'item_categories',
                value: encodeItemTags(categories),
              ),
            );
      });

  Future<void> deleteCategory(String name) => db.transaction(() async {
    if ((await db.select(db.items).get()).any(
      (i) => itemTags(i.category).contains(name),
    )) {
      throw const FormatException('此种类已有物品，无法删除');
    }
    final pref = await (db.select(
      db.preferences,
    )..where((p) => p.key.equals('item_categories'))).getSingleOrNull();
    final categories = configuredItemCategories(pref?.value)..remove(name);
    await db
        .into(db.preferences)
        .insertOnConflictUpdate(
          PreferencesCompanion.insert(
            key: 'item_categories',
            value: encodeItemTags(categories),
          ),
        );
  });
}
