import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/money/money.dart';
import '../../../core/time/business_date.dart';
import '../../../data/database/app_database.dart';

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
    List<String> entryIds = const [],
  }) => db.transaction(() async {
    if (name.trim().isEmpty || name.trim().length > 100) {
      throw const FormatException('物品名称为 1–100 字');
    }
    if (category.trim().length > 80 || note.length > 2000) {
      throw const FormatException('分类或备注过长');
    }
    fractionDigits(currency);
    if (price != null && (price < 0 || price > 999999999999)) {
      throw const FormatException('购入价无效');
    }
    if (purchasedOn != null) ownershipDays(purchasedOn, DateTime.now());
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
            category: Value(category.trim().isEmpty ? '未分类' : category.trim()),
            currency: currency,
            price: Value(price),
            purchasedOn: Value(purchasedOn),
            note: Value(note.trim()),
            photo: Value(photo),
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
}
