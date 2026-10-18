import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/inventory/data/inventory_repository.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';
import 'package:so_account/features/statistics/data/csv_export.dart';

void main() {
  late AppDatabase db;
  late LedgerRepository ledger;
  late InventoryRepository inventory;
  late String account;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    ledger = LedgerRepository(db);
    inventory = InventoryRepository(db);
    await ledger.saveAccount(
      name: '账户',
      kind: accountKinds.first,
      channel: '现金',
      currency: 'CNY',
      openingBalance: 0,
    );
    account = (await db.select(db.accounts).get()).single.id;
  });
  tearDown(() => db.close());
  Future<String> entry({
    EntryKind kind = EntryKind.expense,
    String note = '',
    String date = '2026-10-18',
    int amount = 1234,
  }) => ledger.saveEntry(
    kind: kind,
    amount: amount,
    accountId: account,
    categoryId: '${kind.name}-0',
    date: date,
    note: note,
  );
  test(
    'items are independent; links are unique and deleting entry preserves item',
    () async {
      final expense = await entry();
      final id = await inventory.save(
        name: '耳机',
        category: '数码',
        currency: 'CNY',
        price: 1000,
        purchasedOn: '2026-10-01',
        entryIds: [expense, expense],
      );
      expect((await db.select(db.purchaseLinks).get()).length, 1);
      await ledger.deleteEntry(expense);
      expect((await db.select(db.items).get()).single.id, id);
      expect(await db.select(db.purchaseLinks).get(), isEmpty);
    },
  );
  test('invalid link rolls back the entire item write', () async {
    final income = await entry(kind: EntryKind.income);
    await expectLater(
      inventory.save(
        name: '错误关联',
        category: '',
        currency: 'CNY',
        entryIds: [income],
      ),
      throwsFormatException,
    );
    expect(await db.select(db.items).get(), isEmpty);
    await expectLater(
      inventory.save(
        name: '未来',
        category: '',
        currency: 'CNY',
        purchasedOn: '2099-01-01',
      ),
      throwsFormatException,
    );
  });
  test(
    'CSV periods, grouping and special characters are lossless and safe',
    () async {
      await entry(note: '=HYPERLINK("bad")\n逗号,引号"');
      await entry(amount: 100);
      await entry(date: '2026-11-01', amount: 9999);
      final exporter = CsvExport(db);
      final csv = await exporter.create(ExportPeriod.month, DateTime(2026, 10));
      expect(csv.startsWith('\uFEFF'), isTrue);
      expect(csv, contains("'=HYPERLINK("));
      expect(csv, contains('""bad""'));
      expect(csv, contains('12.34'));
      expect(csv, isNot(contains('99.99')));
      final summary = await exporter.create(
        ExportPeriod.month,
        DateTime(2026, 10),
        summary: true,
      );
      expect(summary, contains('13.34'));
      expect(summary, contains('饮食'));
      final year = await exporter.create(
        ExportPeriod.year,
        DateTime(2026),
        summary: true,
      );
      expect(year, contains('113.33'));
      expect(csvCell('@SUM(A1)'), '"\'@SUM(A1)"');
    },
  );
}
