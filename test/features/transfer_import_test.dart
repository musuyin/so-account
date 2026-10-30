import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/importing/domain/import_plan.dart';
import 'package:so_account/features/importing/domain/import_table.dart';
import 'package:so_account/features/importing/domain/missing_accounts.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';
import 'package:so_account/features/statistics/data/statistics_repository.dart';
import 'package:so_account/features/statistics/domain/report_range.dart';

// Header structure only. All transaction values below are synthetic.
const transferTemplateHeaders = [
  '日期',
  '类型',
  '转出账户',
  '转入账户',
  '金额',
  '手续费',
  '备注',
  '附件1',
  '附件2',
  '附件3',
  '附件4',
  '附件5',
];

const statementHeaders = [
  '日期',
  '收支类型',
  '金额',
  '类别',
  '二级分类',
  '账户',
  '账本',
  '退款',
  '优惠',
  '备注',
  '标签',
  '报销账户',
  '报销金额',
  '报销明细',
  '多币种',
  '地址',
  '创建用户',
  '其他',
  '附件1',
  '附件2',
  '附件3',
  '附件4',
  '附件5',
];
List<String> statementRow(
  Map<String, String> values, {
  bool extended = false,
}) => [
  for (final header in [
    ...statementHeaders,
    if (extended) ...['源账户', '目标账户'],
  ])
    values[header] ?? '',
];

void main() {
  test('provided header structure detects income/expense, never reimbursement as target', () {
    final table = ImportTable.fromRows('账单', [
      statementHeaders,
      statementRow({
        '日期': '2026-10-21',
        '收支类型': '收入',
        '金额': '20',
        '账户': '钱包',
        '类别': '工资',
      }),
    ]);
    final mapping = ImportMapping()..detect(table);
    expect(mapping.columns[ImportField.kind], 1);
    expect(mapping.kindFor(table.rows.single), EntryKind.income);
    expect(mapping.columns[ImportField.account], 5);
    expect(mapping.columns[ImportField.category], 3);
    expect(mapping.columns[ImportField.target], isNull);
    expect(mapping.columns[ImportField.source], isNull);
  });
  test('extended source takes priority for transfers; ordinary rows keep original account', () {
    final table = ImportTable.fromRows('账单', [
      [...statementHeaders, '源账户', '目标账户'],
      statementRow({
        '日期': '2026-10-21',
        '收支类型': '支出',
        '金额': '-12.50',
        '账户': '钱包',
        '源账户': '其他',
      }, extended: true),
      statementRow({
        '日期': '2026-10-21',
        '收支类型': '转账',
        '金额': '-100',
        '账户': '旧账户',
        '源账户': '银行',
        '目标账户': '钱包',
      }, extended: true),
    ]);
    final mapping = ImportMapping()..detect(table);
    expect(
      mapping.sourceAccountValue(table.rows[0], mapping.kindFor(table.rows[0])),
      '钱包',
    );
    expect(
      mapping.sourceAccountValue(table.rows[1], mapping.kindFor(table.rows[1])),
      '银行',
    );
    expect(mapping.value(table.rows[1], ImportField.target), '钱包');
  });
  test(
    'legacy account-as-source and source-only generic files remain compatible',
    () {
      for (final headers in [
        ['日期', '类型', '金额', '账户', '转入账户'],
        ['日期', '类型', '金额', '源账户', '目标账户'],
        ['date', 'type', 'amount', 'source_account', 'target_account'],
      ]) {
        final table = ImportTable.fromRows('test', [
          headers,
          ['2026-10-21', '转帐', '100', '银行', '钱包'],
        ]);
        final mapping = ImportMapping()..detect(table);
        expect(mapping.kindFor(table.rows.single), EntryKind.transfer);
        expect(
          mapping.sourceAccountValue(table.rows.single, EntryKind.transfer),
          '银行',
        );
        expect(mapping.value(table.rows.single, ImportField.target), '钱包');
      }
    },
  );
  test('missing accounts include both transfer roles and ignore targets on ordinary rows', () {
    final table = ImportTable.fromRows('test', [
      ['日期', '收支类型', '金额', '账户', '源账户', '目标账户', '币种'],
      ['2026-10-21', '转账', '100', '', '银行', '钱包', 'CNY'],
      ['2026-10-22', '转账', '10', '', '钱包', '银行', 'CNY'],
      ['2026-10-23', '收入', '20', '工资卡', '', '忽略账户', 'CNY'],
    ]);
    final mapping = ImportMapping()..detect(table);
    final missing = missingImportAccounts(table, mapping, []);
    expect(missing.map((m) => m.name), ['银行', '钱包', '工资卡']);
    expect(missing[0].roles, {'转账源账户', '转账目标账户'});
    expect(missing[1].roles, {'转账目标账户', '转账源账户'});
    expect(missing[0].rows, {2, 3});
    expect(missing[0].currencies, {'CNY'});
    expect(missing[0].firstDate, '2026-10-21');
    expect(missing[2].roles, {'收支账户'});
  });

  late AppDatabase db;
  late LedgerRepository ledger;
  late List<Account> accounts;
  late List<Category> categories;
  late String bank, wallet, usd;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    ledger = LedgerRepository(db);
    Future<String> account(
      String name,
      int balance, {
      String currency = 'CNY',
    }) => ledger.saveAccount(
      name: name,
      kind: '资金账户',
      channel: '现金',
      currency: currency,
      openingBalance: balance,
    );
    bank = await account('银行', 100000);
    wallet = await account('钱包', 10000);
    usd = await account('外币账户', 10000, currency: 'USD');
    accounts = await db.select(db.accounts).get();
    categories = await db.select(db.categories).get();
  });
  tearDown(() => db.close());
  ImportTable transferTable({String kind = '转账', String fee = '1'}) =>
      ImportTable.fromRows('转账', [
        transferTemplateHeaders,
        ['2026-10-21', kind, '银行', '钱包', '100', fee, '示例', '', '', '', '', ''],
      ]);
  test('real transfer header structure detects both roles and fee; repayment requires explicit mapping', () {
    final table = transferTable(kind: '还款');
    final mapping = ImportMapping()..detect(table);
    expect(mapping.columns[ImportField.source], 2);
    expect(mapping.columns[ImportField.target], 3);
    expect(mapping.columns[ImportField.fee], 5);
    expect(mapping.kindFor(table.rows.single), isNull);
    mapping.kinds['还款'] = 'transfer';
    expect(mapping.kindFor(table.rows.single), EntryKind.transfer);
    expect(missingImportAccounts(table, mapping, []).map((a) => a.roles), [
      {'转账源账户'},
      {'转账目标账户'},
    ]);
  });
  test('transfer plus fee commits atomically with correct balances and expense statistics', () async {
    final table = transferTable();
    final mapping = ImportMapping()..detect(table);
    final result = previewImport(
      table,
      mapping,
      accounts,
      categories,
      [],
    ).single;
    expect(result.error, isNull);
    expect(result.entry!.fee!.amount, 100);
    expect(await commitImport(db, [result.entry!]), 1);
    final entries = await db.select(db.entries).get();
    expect(entries.length, 2);
    expect(entries.singleWhere((e) => e.kind == 'transfer').amount, 10000);
    expect(entries.singleWhere((e) => e.kind == 'expense').amount, 100);
    final balances = await ledger.watchBalances().first;
    expect(balances[bank], 89900);
    expect(balances[wallet], 20000);
    final report = await StatisticsRepository(
      db,
    ).load(ReportRange.at(ReportPeriod.month, DateTime(2026, 10, 21)), 'CNY');
    expect(report.expense, 100);
    expect(report.income, 0);
    expect(
      previewImport(
        table,
        mapping,
        accounts,
        categories,
        entries,
      ).single.entry!.duplicate,
      isTrue,
    );
  });
  test('invalid fees fail visibly without corrupting subsequent duplicate detection', () {
    for (final fee in ['-1', 'oops', '1.001', '10000000000']) {
      final table = transferTable(fee: fee);
      final mapping = ImportMapping()..detect(table);
      expect(
        previewImport(table, mapping, accounts, categories, []).single.error,
        contains('手续费'),
      );
    }
    final table = transferTable();
    final mapping = ImportMapping()..detect(table);
    mapping.feeCategory = 'missing';
    expect(
      previewImport(table, mapping, accounts, categories, []).single.error,
      contains('手续费支出分类'),
    );
    expect(
      previewImport(table, mapping, accounts, [], []).single.error,
      contains('手续费支出分类'),
    );
    final zero = transferTable(fee: '0');
    mapping.detect(zero);
    expect(
      previewImport(zero, mapping, accounts, [], []).single.entry!.fee,
      isNull,
    );
  });
  for (final missingFee in [true, false]) {
    test(
      'partial import adds only missing ${missingFee ? 'fee' : 'transfer'}',
      () async {
        final table = transferTable();
        final mapping = ImportMapping()..detect(table);
        final original = previewImport(
          table,
          mapping,
          accounts,
          categories,
          [],
        ).single.entry!;
        final part = missingFee
            ? ImportEntry(
                row: original.row,
                kind: original.kind,
                amount: original.amount,
                accountId: original.accountId,
                date: original.date,
                note: original.note,
                targetId: original.targetId,
              )
            : original.fee!;
        await commitImport(db, [part]);
        final remaining = previewImport(
          table,
          mapping,
          accounts,
          categories,
          await db.select(db.entries).get(),
        ).single.entry!;
        expect(remaining.duplicate, isFalse);
        expect(remaining.suspectedDuplicate, isTrue);
        expect(
          remaining.recordsToImport.single.kind,
          missingFee ? EntryKind.expense : EntryKind.transfer,
        );
        await commitImport(db, [remaining]);
        expect((await db.select(db.entries).get()).length, 2);
        expect((await ledger.watchBalances().first)[bank], 89900);
      },
    );
  }
  test(
    'deleted fee category after preview rolls back transfer and fee',
    () async {
      final table = transferTable();
      final mapping = ImportMapping()..detect(table);
      final entry = previewImport(
        table,
        mapping,
        accounts,
        categories,
        [],
      ).single.entry!;
      await ledger.deleteCategory(entry.fee!.categoryId!);
      await expectLater(commitImport(db, [entry]), throwsFormatException);
      expect(await db.select(db.entries).get(), isEmpty);
    },
  );
  test('distinct notes retain distinct fees; invalid fee does not poison duplicates', () async {
    final table = ImportTable.fromRows('转账', [
      transferTemplateHeaders,
      [
        '2026-10-21',
        '转账',
        '银行',
        '钱包',
        '100',
        '-1',
        'first',
        '',
        '',
        '',
        '',
        '',
      ],
      ['2026-10-21', '转账', '银行', '钱包', '100', '1', 'first', '', '', '', '', ''],
      [
        '2026-10-21',
        '转账',
        '银行',
        '钱包',
        '100',
        '1',
        'second',
        '',
        '',
        '',
        '',
        '',
      ],
    ]);
    final mapping = ImportMapping()..detect(table);
    final plan = previewImport(table, mapping, accounts, categories, []);
    expect(plan.first.error, contains('手续费'));
    expect(plan.skip(1).map((r) => r.entry!.suspectedDuplicate), [
      false,
      false,
    ]);
    await commitImport(db, plan.skip(1).map((r) => r.entry!).toList());
    expect((await db.select(db.entries).get()).length, 4);
    expect((await ledger.watchBalances().first)[bank], 79800);
  });
  test('mixed original template imports one transfer and reconciles balances and statistics', () async {
    final table = ImportTable.fromRows('账单', [
      [...statementHeaders, '源账户', '目标账户'],
      statementRow({
        '日期': '2026-10-21 10:00:00',
        '收支类型': '收入',
        '金额': '20',
        '账户': '钱包',
        '类别': '工资',
      }, extended: true),
      statementRow({
        '日期': '2026-10-21 11:00:00',
        '收支类型': '支出',
        '金额': '-12.50',
        '账户': '钱包',
        '类别': '居住',
      }, extended: true),
      statementRow({
        '日期': '2026-10-21 12:00:00',
        '收支类型': '转账',
        '金额': '-100',
        '源账户': '银行',
        '目标账户': '钱包',
        '类别': '无需分类',
      }, extended: true),
    ]);
    final mapping = ImportMapping()..detect(table);
    final plan = previewImport(table, mapping, accounts, categories, []);
    expect(plan.map((r) => r.error), everyElement(isNull));
    expect(plan.last.entry!.categoryId, isNull);
    expect(await commitImport(db, plan.map((r) => r.entry!).toList()), 3);
    final entries = await db.select(db.entries).get();
    expect(entries.where((e) => e.kind == 'transfer').length, 1);
    expect(
      entries.singleWhere((e) => e.kind == 'transfer').targetAccountId,
      wallet,
    );
    final balances = await ledger.watchBalances().first;
    expect(balances[bank], 90000);
    expect(balances[wallet], 20750);
    expect(balances[bank]! + balances[wallet]!, 110750);
    final report = await StatisticsRepository(
      db,
    ).load(ReportRange.at(ReportPeriod.month, DateTime(2026, 10, 21)), 'CNY');
    expect(report.income, 2000);
    expect(report.expense, 1250);
    expect(report.surplus, 750);
  });
  test('missing target, identical accounts, and currency mismatch are explicit row errors', () {
    final noTarget = ImportTable.fromRows('test', [
      ['日期', '类型', '金额', '源账户'],
      ['2026-10-21', '转账', '100', '银行'],
    ]);
    final mapping = ImportMapping()..detect(noTarget);
    expect(
      previewImport(noTarget, mapping, accounts, categories, []).single.error,
      contains('目标账户列'),
    );
    final table = ImportTable.fromRows('test', [
      ['日期', '类型', '金额', '源账户', '目标账户'],
      ['2026-10-21', '转账', '100', '银行', ''],
      ['2026-10-21', '转账', '100', '银行', '银行'],
      ['2026-10-21', '转账', '100', '银行', '外币账户'],
    ]);
    mapping.detect(table);
    final plan = previewImport(table, mapping, accounts, categories, []);
    expect(plan[0].error, contains('缺少目标账户'));
    expect(plan[1].error, contains('另一个同币种账户'));
    expect(plan[2].error, contains('另一个同币种账户'));
  });
  test('manual mapping resolves renamed destination; duplicate detection retains direction', () async {
    final table = ImportTable.fromRows('test', [
      ['日期', '收支类型', '金额', '源账户', '目标账户'],
      ['2026-10-21', '转账', '100', '银行', '来自文件的钱包'],
      ['2026-10-21', '转账', '100', '银行', '来自文件的钱包'],
      ['2026-10-21', '转账', '100', '来自文件的钱包', '银行'],
    ]);
    final mapping = ImportMapping()..detect(table);
    mapping.accounts['来自文件的钱包'] = wallet;
    expect(missingImportAccounts(table, mapping, accounts), isEmpty);
    final plan = previewImport(table, mapping, accounts, categories, []);
    expect(plan.map((r) => r.entry!.duplicate), [false, true, false]);
    await commitImport(db, [plan.first.entry!]);
    final existing = await db.select(db.entries).get();
    expect(
      previewImport(
        table,
        mapping,
        accounts,
        categories,
        existing,
      ).first.entry!.duplicate,
      isTrue,
    );
  });
  test(
    'destination currency changed after preview rolls back the entire batch',
    () async {
      final table = ImportTable.fromRows('test', [
        ['日期', '类型', '金额', '源账户', '目标账户'],
        ['2026-10-21', '转账', '100', '银行', '钱包'],
        ['2026-10-21', '转账', '10', '银行', '外币账户'],
      ]);
      await (db.update(db.accounts)..where((a) => a.id.equals(usd))).write(
        const AccountsCompanion(currency: Value('CNY')),
      );
      accounts = await db.select(db.accounts).get();
      final mapping = ImportMapping()..detect(table);
      final plan = previewImport(table, mapping, accounts, categories, []);
      expect(plan.map((r) => r.error), everyElement(isNull));
      await db.customStatement(
        "UPDATE accounts SET currency='USD' WHERE id=?",
        [usd],
      );
      await expectLater(
        commitImport(db, plan.map((r) => r.entry!).toList()),
        throwsFormatException,
      );
      expect(await db.select(db.entries).get(), isEmpty);
      final balances = await ledger.watchBalances().first;
      expect(balances[bank], 100000);
      expect(balances[wallet], 10000);
    },
  );
}
