import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/importing/domain/import_plan.dart';
import 'package:so_account/features/importing/domain/import_table.dart';
import 'package:so_account/features/importing/domain/missing_accounts.dart';

void main() {
  test('creating an account rejects duplicate names per currency and invalid opening balances', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final repository = LedgerRepository(db);
    Future<String> save({String currency = 'CNY', int balance = 0}) =>
        repository.saveAccount(
          name: '钱包',
          kind: '资金账户',
          channel: '现金',
          currency: currency,
          openingBalance: balance,
        );
    try {
      await save();
      await expectLater(save(), throwsFormatException);
      await expectLater(
        save(currency: 'USD', balance: 1000000000000),
        throwsFormatException,
      );
      await save(currency: 'USD');
      expect((await db.select(db.accounts).get()).length, 2);
    } finally {
      await db.close();
    }
  });
  test('missing accounts are grouped and transfer targets included only for transfers', () {
    final table = ImportTable.fromRows('test', [
      ['日期', '金额', '账户', '转入账户', '类型', '币种'],
      ['2026-01-02', '2', '新钱包', '忽略', '支出', 'CNY'],
      ['2026-01-01', '1', '新钱包', '储蓄', '转账', 'CNY'],
    ]);
    final map = ImportMapping()..detect(table);
    final missing = missingImportAccounts(table, map, []);
    expect(missing.map((m) => m.name), ['新钱包', '储蓄']);
    expect(missing.first.rows, {2, 3});
    expect(missing.first.firstDate, '2026-01-01');
    expect(missing.first.currencies, {'CNY'});
    const account = Account(
      customChannel: '',
      id: 'a',
      avatar: '',
      name: '别名账户',
      kind: '资金账户',
      channel: '现金',
      currency: 'CNY',
      openingBalance: 0,
    );
    map.accounts['新钱包'] = 'a';
    expect(missingImportAccounts(table, map, [account]).map((m) => m.name), [
      '储蓄',
    ]);
  });
}
