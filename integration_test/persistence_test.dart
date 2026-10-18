import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uuid/uuid.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('device database close and reopen retains a ledger entry', (
    tester,
  ) async {
    // Use a unique synthetic account and remove it at the end. Existing data is
    // never erased, and this test does not require a fixture database.
    var db = AppDatabase();
    String? entryId, accountId, categoryId;
    try {
      final repo = LedgerRepository(db);
      final name = '设备测试-${const Uuid().v4()}';
      await repo.saveCategory(name, 'expense');
      categoryId = (await db.select(db.categories).get())
          .firstWhere((c) => c.name == name)
          .id;
      await repo.saveAccount(
        name: name,
        kind: accountKinds.first,
        channel: '现金',
        currency: 'CNY',
        openingBalance: 10000,
      );
      accountId = (await db.select(db.accounts).get())
          .firstWhere((a) => a.name == name)
          .id;
      entryId = await repo.saveEntry(
        kind: EntryKind.expense,
        amount: 1234,
        accountId: accountId,
        date: '2026-10-18',
        categoryId: categoryId,
        note: '人工测试数据',
      );
      await db.close();
      db = AppDatabase();
      final entry = await (db.select(
        db.entries,
      )..where((e) => e.id.equals(entryId!))).getSingle();
      expect(entry.amount, 1234);
      expect(
        (await LedgerRepository(db).watchBalances().first)[accountId],
        8766,
      );
    } finally {
      if (entryId != null) await LedgerRepository(db).deleteEntry(entryId);
      if (accountId != null) {
        await LedgerRepository(db).deleteAccount(accountId);
      }
      if (categoryId != null)
        await LedgerRepository(db).deleteCategory(categoryId);
      await db.close();
    }
  });
}
