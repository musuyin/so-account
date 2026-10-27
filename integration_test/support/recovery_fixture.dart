import 'dart:convert';

import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';
import 'package:so_account/features/inventory/data/inventory_repository.dart';
import 'package:so_account/features/goals/data/goals_repository.dart';
import 'package:so_account/platform/media/media_store.dart';

Future<void> seedRecoveryFixture(AppDatabase db, MediaStore media) async {
  final ledger = LedgerRepository(db);
  Future<String> account(String name, String currency) => ledger.saveAccount(
    name: name,
    kind: '资金账户',
    channel: '现金',
    currency: currency,
    openingBalance: 100000,
  );
  final wallet = await account('合成钱包', 'CNY');
  final bank = await account('合成银行卡', 'CNY');
  final usd = await account('合成外币', 'USD');
  await ledger.saveEntry(
    kind: EntryKind.income,
    amount: 10000,
    accountId: wallet,
    categoryId: 'income-0',
    date: '2026-10-01',
  );
  final expense = await ledger.saveEntry(
    kind: EntryKind.expense,
    amount: 1234,
    accountId: wallet,
    categoryId: 'expense-0',
    date: '2026-10-01',
  );
  await ledger.saveEntry(
    kind: EntryKind.expense,
    amount: 200,
    accountId: usd,
    categoryId: 'expense-0',
    date: '2026-10-01',
  );
  await ledger.saveEntry(
    kind: EntryKind.transfer,
    amount: 5000,
    accountId: wallet,
    targetAccountId: bank,
    date: '2026-10-02',
  );
  final loan = await ledger.saveEntry(
    kind: EntryKind.borrow,
    amount: 20000,
    accountId: wallet,
    counterparty: '合成往来',
    date: '2026-10-02',
  );
  await ledger.saveEntry(
    kind: EntryKind.repay,
    amount: 5000,
    accountId: wallet,
    debtId: loan,
    date: '2026-10-03',
  );
  final balances = await ledger.balances();
  await ledger.adjustBalance(
    accountId: wallet,
    desiredBalance: balances[wallet]! + 34,
    expectedBalance: balances[wallet]!,
    at: DateTime(2026, 10, 4),
  );
  await ledger.archiveAccount(bank);
  final photo = media.resolve('media/synthetic.png');
  await photo.parent.create(recursive: true);
  await photo.writeAsBytes(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a+a8AAAAASUVORK5CYII=',
    ),
    flush: true,
  );
  await InventoryRepository(db).save(
    name: '合成物品',
    category: '生活',
    currency: 'CNY',
    price: 1234,
    purchasedOn: '2026-10-01',
    photo: 'media/synthetic.png',
    entryIds: [expense],
  );
  await GoalsRepository(db).save(
    name: '合成攒钱',
    kind: 'saving',
    currency: 'CNY',
    target: 100000,
    initialSaved: 1234,
  );
  await db
      .into(db.preferences)
      .insertOnConflictUpdate(
        PreferencesCompanion.insert(key: 'theme', value: 'dark'),
      );
}

/// Sorted complete rows, normalized photo paths plus actual photo bytes. IDs,
/// audit stamps, balances, original loans, links and preferences all participate.
Future<Map<String, Object?>> recoverySnapshot(
  AppDatabase db,
  MediaStore media,
) => db.transaction(() async {
  final result = <String, Object?>{};
  for (final table in db.allTables) {
    final rows = await db
        .customSelect('SELECT * FROM "${table.actualTableName}"')
        .get();
    final normalized = <String>[];
    for (final row in rows) {
      final data = Map<String, Object?>.from(row.data);
      if (table.actualTableName == 'items' && data['photo'] != null) {
        final file = media.resolve(data['photo']! as String);
        if (!await file.exists()) {
          throw StateError('Committed photo is missing');
        }
        data['photo'] = base64Encode(await file.readAsBytes());
      }
      normalized.add(jsonEncode(data));
    }
    normalized.sort();
    result[table.actualTableName] = normalized;
  }
  final balances = await LedgerRepository(db).balances();
  result['balances'] = {
    for (final id in balances.keys.toList()..sort()) id: balances[id],
  };
  return result;
});
