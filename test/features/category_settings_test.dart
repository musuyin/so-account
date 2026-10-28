import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/core/category_preferences.dart';
import 'package:so_account/data/app_snapshot.dart';
import 'package:so_account/data/category_settings_store.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/backup/data/backup_service.dart';
import 'package:so_account/features/backup/domain/backup_codec.dart';
import 'package:so_account/features/inventory/data/inventory_repository.dart';
import 'package:so_account/features/inventory/domain/item_categories.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/platform/media/media_store.dart';

Future<AppSnapshot> snapshot(AppDatabase db) async => AppSnapshot(
  [],
  await db.select(db.categories).get(),
  [],
  [],
  await db.select(db.items).get(),
  [],
  await db.select(db.preferences).get(),
);

void main() {
  test('income/expense orders stay isolated; rename, append and deletion retain stable IDs/icons', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LedgerRepository(db);
    final initial = await snapshot(db);
    final expense = initial.categories
        .where((c) => c.kind == 'expense')
        .map((c) => c.id)
        .toList();
    final income = initial.categories
        .where((c) => c.kind == 'income')
        .map((c) => c.id)
        .toList();
    final settings = CategorySettingsStore(db);
    await settings.write(expenseOrderKey, []);
    await repo.saveCategory('合成旧账本改名', 'expense', id: expense.first);
    expect(
      (await snapshot(db)).categories
          .where((c) => c.kind == 'expense')
          .map((c) => c.id),
      expense,
    );
    await repo.reorderCategories('expense', [
      income.first,
      expense.last,
      expense.last,
      'retired',
      ...expense,
    ]);
    var data = await snapshot(db);
    expect(
      data.categories.where((c) => c.kind == 'expense').first.id,
      expense.last,
    );
    expect(
      data.categories.where((c) => c.kind == 'income').map((c) => c.id),
      income,
    );
    await repo.saveCategory(
      '合成新名称',
      'expense',
      id: expense.last,
      iconId: 'camera',
    );
    await repo.saveCategory('合成再次改名', 'expense', id: expense.last);
    await repo.saveCategory('合成新增', 'expense', iconId: 'book');
    data = await snapshot(db);
    expect(
      data.categories.where((c) => c.kind == 'expense').first.id,
      expense.last,
    );
    expect(data.categoryIconId(expense.last), 'camera');
    final added = data.categories.where((c) => c.kind == 'expense').last;
    expect(added.name, '合成新增');
    await expectLater(
      repo.saveCategory('不允许跨组', 'income', id: expense.last),
      throwsFormatException,
    );
    await repo.deleteCategory(added.id);
    expect(
      decodeCategoryOrder(await settings.read(expenseOrderKey)),
      isNot(contains(added.id)),
    );
    expect(
      decodeCategoryIcons(await settings.read(categoryIconsKey)),
      isNot(contains(added.id)),
    );
  });

  test('item source uses configured order before all historical tags; rename updates every reference atomically', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final settings = CategorySettingsStore(db);
    final repo = InventoryRepository(db);
    await settings.write(itemCategoriesKey, ['配置乙', '配置甲']);
    await repo.save(
      name: '合成物品',
      category: encodeItemTags(['历史丙', '配置甲']),
      currency: 'CNY',
    );
    expect((await snapshot(db)).itemCategoryNames, ['配置乙', '配置甲', '历史丙']);
    await repo.reorderCategories(['历史丙', '历史丙', '失效', '配置乙', '配置甲']);
    await repo.saveCategory('历史改名', previous: '历史丙', iconId: 'phone');
    await repo.saveCategory('再次改名', previous: '历史改名');
    var data = await snapshot(db);
    expect(data.itemCategoryNames, ['再次改名', '配置乙', '配置甲']);
    expect(validateItemCategories('["配置甲","配置甲"]'), ['配置甲']);
    expect(data.itemCategoryIconId('再次改名'), 'phone');
    expect(data.itemCategoryIconId('历史改名'), isNull);
    expect(itemTags(data.items.single.category), ['再次改名', '配置甲']);
    await expectLater(
      repo.saveCategory('配置乙', previous: '再次改名', iconId: 'book'),
      throwsFormatException,
    );
    data = await snapshot(db);
    expect(data.itemCategoryNames.first, '再次改名');
    expect(data.itemCategoryIconId('再次改名'), 'phone');
    await db.customStatement(
      "CREATE TEMP TRIGGER fail_icon_save BEFORE UPDATE ON preferences WHEN NEW.key = 'item_category_icons' BEGIN SELECT RAISE(ABORT, 'simulated write failure'); END",
    );
    await expectLater(
      repo.saveCategory('失败改名', previous: '再次改名', iconId: 'camera'),
      throwsA(isA<Exception>()),
    );
    data = await snapshot(db);
    expect(data.itemCategoryNames.first, '再次改名');
    expect(data.itemCategoryIconId('再次改名'), 'phone');
    expect(itemTags(data.items.single.category), ['再次改名', '配置甲']);
    await db.customStatement('DROP TRIGGER fail_icon_save');
    await expectLater(repo.deleteCategory('再次改名'), throwsFormatException);
    await repo.saveCategory('末尾种类', iconId: 'book');
    expect((await snapshot(db)).itemCategoryNames.last, '末尾种类');
    await repo.deleteCategory('末尾种类');
    expect((await snapshot(db)).itemCategoryIconId('末尾种类'), isNull);
  });

  test('disk reopen and backup restore preserve orders/icons; old and future icon backups remain readable', () async {
    final dir = await Directory.systemTemp.createTemp('so_category_settings_');
    final file = File('${dir.path}/ledger.db');
    var db = AppDatabase(NativeDatabase(file));
    try {
      var data = await snapshot(db);
      final id = data.categories.last.id;
      final kind = data.categories.last.kind;
      await LedgerRepository(db).reorderCategories(kind, [id]);
      await LedgerRepository(db)
          .saveCategory('合成改名', kind, id: id, iconId: 'future-icon');
      await InventoryRepository(db).saveCategory('合成种类', iconId: 'camera');
      await InventoryRepository(db).reorderCategories(['合成种类']);
      await db.close();
      db = AppDatabase(NativeDatabase(file));
      data = await snapshot(db);
      expect(data.categories.where((c) => c.kind == kind).first.id, id);
      expect(data.itemCategoryNames.first, '合成种类');
      expect(data.categoryIconId(id), 'future-icon');
      final service = BackupService(
        db,
        MediaStore(Directory('${dir.path}/media')),
      );
      final bytes = await service.export();
      await LedgerRepository(db).reorderCategories(
        kind,
        data.categories
            .where((c) => c.kind == kind)
            .map((c) => c.id)
            .toList()
            .reversed
            .toList(),
      );
      await service.restore(bytes);
      expect(
        (await snapshot(db)).categories.where((c) => c.kind == kind).first.id,
        id,
      );
      expect((await snapshot(db)).itemCategoryIconId('合成种类'), 'camera');
      final files = decodeBackup(bytes);
      final json =
          jsonDecode(utf8.decode(files['data.json']!)) as Map<String, dynamic>;
      (json['preferences'] as List).removeWhere(
        (p) => [
          expenseOrderKey,
          incomeOrderKey,
          categoryIconsKey,
          itemCategoryIconsKey,
        ].contains(p['key']),
      );
      files['data.json'] = Uint8List.fromList(utf8.encode(jsonEncode(json)));
      await service.restore(encodeBackup(files));
      expect(
        (await snapshot(db)).categories,
        hasLength(data.categories.length),
      );
      expect((await snapshot(db)).categoryIconId(id), isNull);
      // Malformed new settings must fail before touching production data.
      (json['preferences'] as List).add({
        'key': expenseOrderKey,
        'value': '[1]',
      });
      files['data.json'] = Uint8List.fromList(utf8.encode(jsonEncode(json)));
      await expectLater(
        service.restore(encodeBackup(files)),
        throwsFormatException,
      );
      expect(
        (await snapshot(db)).categories,
        hasLength(data.categories.length),
      );
    } finally {
      await db.close();
      await dir.delete(recursive: true);
    }
  });
}
