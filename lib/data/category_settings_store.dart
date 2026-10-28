import 'dart:convert';

import '../core/category_preferences.dart';
import '../features/inventory/domain/item_categories.dart';
import 'database/app_database.dart';

/// Call mutations inside the owning repository's transaction so names, order
/// and icons become visible together, including during rename and deletion.
class CategorySettingsStore {
  CategorySettingsStore(this.db);
  final AppDatabase db;

  Future<String?> read(String key) async => (await (db.select(
    db.preferences,
  )..where((p) => p.key.equals(key))).getSingleOrNull())?.value;

  Future<void> write(String key, Object value) => db
      .into(db.preferences)
      .insertOnConflictUpdate(
        PreferencesCompanion.insert(key: key, value: jsonEncode(value)),
      );

  Future<void> icon(
    String key,
    String id,
    String? iconId, {
    String? previous,
  }) async {
    final icons = decodeCategoryIcons(await read(key));
    final old = previous == null ? null : icons.remove(previous);
    if (iconId != null || old != null) icons[id] = iconId ?? old!;
    await write(key, icons);
  }

  Future<void> removeIcon(String key, String id) async {
    final icons = decodeCategoryIcons(await read(key))..remove(id);
    await write(key, icons);
  }

  Future<List<String>> itemCategories() async => resolveCategoryOrder([
    ...configuredItemCategories(await read(itemCategoriesKey)),
    ...(await db.select(db.items).get()).expand((i) => itemTags(i.category)),
  ], []);

  Future<void> ledgerOrder(String kind, Iterable<String> order) async {
    if (!['expense', 'income'].contains(kind)) {
      throw const FormatException('分类类型无效');
    }
    // Use the same insertion order as the shared snapshot. A filtered SQL
    // query can choose the (kind, name) index and silently alphabetize old data.
    final live = (await db.select(db.categories).get())
        .where((c) => c.kind == kind)
        .map((c) => c.id);
    await write('category_order_$kind', resolveCategoryOrder(live, order));
  }
}
