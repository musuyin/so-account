import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/core/time/business_date.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/inventory/domain/item_categories.dart';
import 'package:so_account/features/inventory/domain/new_purchase_item.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';

void main() {
  late AppDatabase db;
  late LedgerRepository repo;
  late String accountId;
  final today = dateKey(DateTime.now());
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = LedgerRepository(db);
    accountId = await repo.saveAccount(
      name: '美元钱包',
      kind: '资金账户',
      channel: '现金',
      currency: 'USD',
      openingBalance: 10000,
    );
  });
  tearDown(() => db.close());

  Future<String> save(
    NewPurchaseItem? item, {
    String? id,
    int amount = 2000,
    String? date,
    String note = '',
  }) => repo.saveEntry(
    id: id,
    kind: EntryKind.expense,
    amount: amount,
    accountId: accountId,
    categoryId: 'expense-0',
    date: date ?? today,
    newItem: item,
    note: note,
  );

  test('item and link inherit expense date and currency without assigning its amount', () async {
    final entryId = await save(
      const NewPurchaseItem(name: '键盘', category: '数码产品'),
    );
    final item = (await db.select(db.items).get()).single;
    expect(item.name, '键盘');
    expect(itemTags(item.category), ['数码产品']);
    expect(item.currency, 'USD');
    expect(item.purchasedOn, today);
    expect(item.price, isNull);
    final link = (await db.select(db.purchaseLinks).get()).single;
    expect(link.itemId, item.id);
    expect(link.entryId, entryId);
    expect((await repo.balances())[accountId], 8000);
  });

  test('consumable keeps its own price and optional quantity', () async {
    await save(
      const NewPurchaseItem(
        name: '洗发水',
        category: '日用品',
        useType: 'consumable',
        price: 1250,
        quantity: '500',
        unit: 'ml',
      ),
    );
    final item = (await db.select(db.items).get()).single;
    expect(item.useType, 'consumable');
    expect(item.price, 1250);
    expect(item.quantity, '500');
    expect(item.unit, 'ml');
    expect(item.status, 'active');
    expect((await repo.balances())[accountId], 8000);
  });

  test(
    'invalid item rolls back the expense and retry creates exactly one pair',
    () async {
      await expectLater(
        save(const NewPurchaseItem(name: '', category: '日用品')),
        throwsFormatException,
      );
      expect(await db.select(db.entries).get(), isEmpty);
      expect(await db.select(db.items).get(), isEmpty);
      expect(await db.select(db.purchaseLinks).get(), isEmpty);
      expect((await repo.balances())[accountId], 10000);
      await save(const NewPurchaseItem(name: '杯子', category: '日用品'));
      expect((await db.select(db.entries).get()).length, 1);
      expect((await db.select(db.items).get()).length, 1);
      expect((await db.select(db.purchaseLinks).get()).length, 1);
    },
  );

  test('a link write failure rolls back both newly inserted rows', () async {
    await db.customStatement(
      "CREATE TRIGGER reject_purchase_link BEFORE INSERT ON purchase_links BEGIN SELECT RAISE(ABORT, 'synthetic link failure'); END;",
    );
    await expectLater(
      save(const NewPurchaseItem(name: '杯子', category: '日用品')),
      throwsA(isA<Exception>()),
    );
    expect(await db.select(db.entries).get(), isEmpty);
    expect(await db.select(db.items).get(), isEmpty);
    expect(await db.select(db.purchaseLinks).get(), isEmpty);
    expect((await repo.balances())[accountId], 10000);
  });

  test('failed item creation also rolls back an edited expense and preserves old links', () async {
    final id = await save(
      const NewPurchaseItem(name: '原有物品', category: '日用品'),
      note: '原备注',
    );
    await expectLater(
      save(
        const NewPurchaseItem(name: '', category: '日用品'),
        id: id,
        amount: 4000,
        note: '不应保存',
      ),
      throwsFormatException,
    );
    final entry = (await db.select(db.entries).get()).single;
    expect(entry.amount, 2000);
    expect(entry.note, '原备注');
    expect((await db.select(db.items).get()).single.name, '原有物品');
    expect((await db.select(db.purchaseLinks).get()).length, 1);
    await save(null, id: id, note: '普通编辑');
    expect((await db.select(db.items).get()).length, 1);
    expect((await db.select(db.purchaseLinks).get()).length, 1);
  });

  test(
    'missing item type and non-expense kinds cannot create purchase records',
    () async {
      await expectLater(
        save(const NewPurchaseItem(name: '杯子', category: '')),
        throwsFormatException,
      );
      for (final kind in EntryKind.values.where(
        (k) => k != EntryKind.expense,
      )) {
        await expectLater(
          repo.saveEntry(
            kind: kind,
            amount: 100,
            accountId: accountId,
            date: today,
            newItem: const NewPurchaseItem(name: '物品', category: '日用品'),
          ),
          throwsFormatException,
        );
      }
      expect(await db.select(db.entries).get(), isEmpty);
      expect(await db.select(db.items).get(), isEmpty);
    },
  );

  test(
    'future purchase date and invalid quantity cannot leave a partial expense',
    () async {
      await expectLater(
        save(
          const NewPurchaseItem(name: '杯子', category: '日用品'),
          date: dateKey(DateTime.now().add(const Duration(days: 1))),
        ),
        throwsFormatException,
      );
      await expectLater(
        save(
          const NewPurchaseItem(
            name: '洗发水',
            category: '日用品',
            useType: 'consumable',
            quantity: '0',
            unit: 'ml',
          ),
        ),
        throwsFormatException,
      );
      expect(await db.select(db.entries).get(), isEmpty);
      expect(await db.select(db.items).get(), isEmpty);
      expect((await repo.balances())[accountId], 10000);
    },
  );
}
