import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/importing/domain/import_plan.dart';
import 'package:so_account/features/importing/domain/import_table.dart';
import 'package:so_account/features/importing/domain/missing_accounts.dart';

void main() {
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
