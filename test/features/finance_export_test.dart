import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';
import 'package:so_account/features/statistics/data/finance_export.dart';
import 'package:so_account/features/statistics/data/finance_xlsx.dart';
import 'package:xml/xml.dart';

void main() {
  late AppDatabase db;
  late LedgerRepository ledger;
  late FinanceExportRepository exports;
  late String cash, credit, archived, investment;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    ledger = LedgerRepository(db);
    exports = FinanceExportRepository(db);
    cash = await ledger.saveAccount(
      name: '合成现金',
      kind: '资金账户',
      channel: '现金',
      currency: 'CNY',
      openingBalance: 100000,
    );
    credit = await ledger.saveAccount(
      name: '合成信用',
      kind: '信贷账户',
      channel: '信用卡',
      currency: 'CNY',
      openingBalance: -20000,
    );
    archived = await ledger.saveAccount(
      name: '合成归档',
      kind: '资金账户',
      channel: '现金',
      currency: 'CNY',
      openingBalance: 10000,
    );
    investment = await ledger.saveAccount(
      name: '合成投资',
      kind: '投资理财',
      channel: '基金',
      currency: 'CNY',
      openingBalance: 30000,
    );
    await ledger.saveAccount(
      name: '外币排除',
      kind: '资金账户',
      channel: '现金',
      currency: 'USD',
      openingBalance: 999999,
    );
    for (final row in [
      (EntryKind.income, 2000, '2026-09-01'),
      (EntryKind.expense, 1000, '2026-09-30'),
      (EntryKind.income, 50000, '2026-10-01'),
      (EntryKind.expense, 10000, '2026-10-31'),
      (EntryKind.expense, 700, '2026-11-01'),
    ]) {
      await ledger.saveEntry(
        kind: row.$1,
        amount: row.$2,
        date: row.$3,
        accountId: cash,
        categoryId: '${row.$1.name}-0',
      );
    }
    await ledger.saveEntry(
      kind: EntryKind.income,
      amount: 300,
      date: '2026-10-15',
      accountId: archived,
      categoryId: 'income-0',
    );
    await ledger.archiveAccount(archived);
  });
  tearDown(() => db.close());

  Future<FinanceExportData> comparison() =>
      exports.load('CNY', DateTime(2026, 9), DateTime(2026, 11));

  test('monthly cutoff, full category list, archived accounts and currency isolation', () async {
    final data = await comparison();
    expect(data.months.map((m) => m.totalIncome), [2000, 50300]);
    expect(data.months.map((m) => m.totalExpense), [1000, 10000]);
    expect(data.months.map((m) => m.totalAssets), [141000, 181300]);
    expect(data.months.map((m) => m.totalDebt), [20000, 20000]);
    expect(
      data.incomeColumns.length,
      (await db.select(db.categories).get())
          .where((c) => c.kind == 'income')
          .length,
    );
    expect(data.assetColumns.any((c) => c.name.contains('已归档')), isTrue);
    expect(data.assetColumns.any((c) => c.name.contains('外币')), isFalse);
    expect(data.assetColumns.any((c) => c.name.contains('买入成本')), isTrue);
  });

  test('transfers, loans, reimbursement, costs and corrections preserve net assets', () async {
    Future<String> principal(EntryKind kind, int amount) => ledger.saveEntry(
      kind: kind,
      amount: amount,
      accountId: cash,
      date: '2026-10-03',
      counterparty: '合成往来',
    );
    final borrow = await principal(EntryKind.borrow, 7000);
    final lend = await principal(EntryKind.lend, 3000);
    final reimburse = await principal(EntryKind.reimburse, 4000);
    for (final row in [
      (EntryKind.repay, 2000, borrow),
      (EntryKind.collect, 1000, lend),
      (EntryKind.reimbursement, 500, reimburse),
    ]) {
      await ledger.saveEntry(
        kind: row.$1,
        amount: row.$2,
        debtId: row.$3,
        accountId: cash,
        date: '2026-10-20',
      );
    }
    await ledger.saveEntry(
      kind: EntryKind.transfer,
      amount: 5000,
      accountId: cash,
      targetAccountId: credit,
      date: '2026-10-20',
    );
    final product = await ledger.saveInvestmentProduct(
      accountId: investment,
      name: '合成产品',
      kind: '基金',
    );
    for (final row in [(EntryKind.invest, 2000), (EntryKind.redeem, 1000)]) {
      await ledger.saveEntry(
        kind: row.$1,
        amount: row.$2,
        accountId: cash,
        targetAccountId: investment,
        investmentProductId: product,
        date: '2026-10-21',
      );
    }
    await db
        .into(db.balanceAdjustments)
        .insert(
          BalanceAdjustmentsCompanion.insert(
            id: 'synthetic-correction',
            accountId: cash,
            beforeBalance: 1000,
            afterBalance: 2000,
            delta: 1000,
            date: '2026-10-31',
            createdAt: 1,
          ),
        );
    final data = await comparison();
    final month = data.months.last;
    expect(month.totalIncome, 50300);
    expect(month.totalExpense, 10000);
    expect(month.totalAssets, 182300);
    expect(month.totalDebt, 20000);
    expect(month.netAssets - data.months.first.netAssets, 40300 + 1000);
    final all = await exports.load(
      'CNY',
      DateTime(2026, 9),
      DateTime(2026, 12),
    );
    final live = await ledger.balances();
    for (final a in (await db.select(db.accounts).get()).where(
      (a) => a.currency == 'CNY',
    )) {
      final signed =
          all.months.last.assets[a.id]! - all.months.last.debt[a.id]!;
      expect(signed, a.channel == '应付款' ? -live[a.id]! : live[a.id]);
    }
  });

  test(
    'account crossing zero appears on both sides without double counting',
    () async {
      final cash2 = await ledger.saveAccount(
        name: '跨零账户',
        kind: '资金账户',
        channel: '现金',
        currency: 'CNY',
        openingBalance: 200,
      );
      await ledger.saveEntry(
        kind: EntryKind.expense,
        amount: 500,
        accountId: cash2,
        categoryId: 'expense-0',
        date: '2026-10-31',
      );
      final data = await comparison();
      expect(data.assetColumns.any((c) => c.id == cash2), isTrue);
      expect(data.debtColumns.any((c) => c.id == cash2), isTrue);
      expect(data.months.first.assets[cash2], 200);
      expect(data.months.first.debt[cash2], 0);
      expect(data.months.last.assets[cash2], 0);
      expect(data.months.last.debt[cash2], 300);
    },
  );

  test(
    'growth rules, negative net income, escaped labels and appended notes',
    () async {
      await ledger.saveCategory('含|分隔\n与**标记', 'expense', id: 'expense-0');
      final text = monthlyMarkdown(await comparison(), notes: '月末说明\n第二行');
      expect(text, contains('| 总收入 | 503.00 | 20.00 | 2415.00% |'));
      expect(text, contains('含&#124;分隔<br>与&#42;&#42;标记'));
      expect(text, endsWith('## 说明\n\n月末说明\n第二行\n'));
      expect(exportGrowth(0, 0), '0.00%');
      expect(exportGrowth(20, 0), 'NULL');
      expect(exportGrowth(-50, 100), '-150.00%');
      expect(exportGrowth(-100, -50), '100.00%');
      expect(exportGrowth(0, 50), '-100.00%');
    },
  );

  test(
    'privacy hides asset totals, detail, shares and growth in copied text',
    () async {
      final text = monthlyMarkdown(await comparison(), hideAssets: true);
      expect(text, contains('| 总资产 | •••• | •••• | •••• |'));
      final detail = text.split('## 资产明细').last.split('## 统计口径').first;
      expect(detail, isNot(contains('1813.00')));
      expect(detail, isNot(contains('100%')));
      expect(detail, contains('••••'));
      expect(text, contains('| 总收入 | 503.00 | 20.00 |'));
    },
  );

  test(
    'all history fills empty months and includes future dates and latest edits',
    () async {
      var all = await exports.loadAll('CNY', DateTime(2026, 10));
      expect(all.months.map((m) => m.date.month), [9, 10, 11]);
      await ledger.saveCategory('新增类别', 'expense');
      await db
          .into(db.balanceAdjustments)
          .insert(
            BalanceAdjustmentsCompanion.insert(
              id: 'future',
              accountId: cash,
              beforeBalance: 0,
              afterBalance: 5,
              delta: 5,
              date: '2027-02-01',
              createdAt: 1,
            ),
          );
      all = await exports.loadAll('CNY', DateTime(2026, 10));
      expect(all.months.length, 6);
      expect(all.months[3].totalIncome, 0);
      expect(all.expenseColumns.last.name, '新增类别');
      expect(all.months.last.totalAssets - all.months[4].totalAssets, 5);
      final empty = await exports.loadAll('EUR', DateTime(2026, 10));
      expect(empty.months.length, 1);
      expect(empty.months.single.netAssets, 0);
    },
  );

  test(
    'calendar year, January previous month and leap February are exact',
    () async {
      final year = await exports.load('CNY', DateTime(2026), DateTime(2027));
      expect(year.months.length, 12);
      expect(year.months.fold<int>(0, (s, m) => s + m.totalExpense), 11700);
      final january = await exports.load(
        'CNY',
        DateTime(2025, 12),
        DateTime(2026, 2),
      );
      expect(monthlyMarkdown(january), contains('上月：2025-12'));
      await ledger.saveEntry(
        kind: EntryKind.income,
        amount: 55,
        accountId: cash,
        categoryId: 'income-0',
        date: '2024-02-29',
      );
      final leap = await exports.load(
        'CNY',
        DateTime(2024, 2),
        DateTime(2024, 3),
      );
      expect(leap.months.single.totalIncome, 55);
    },
  );

  test(
    'JPY numeric values and xlsx formulas extend beyond Z; labels are literal',
    () async {
      final yen = await ledger.saveAccount(
        name: '=SUM(1,2)&<合成>',
        kind: '资金账户',
        channel: '现金',
        currency: 'JPY',
        openingBalance: 8000,
      );
      for (var i = 0; i < 30; i++) {
        await ledger.saveCategory('合成分类$i', 'expense');
      }
      await ledger.saveEntry(
        kind: EntryKind.expense,
        amount: 123,
        accountId: yen,
        categoryId: 'expense-0',
        date: '2026-10-01',
      );
      final data = await exports.load('JPY', DateTime(2026), DateTime(2027));
      final bytes = financeXlsx(data);
      final zip = ZipDecoder().decodeBytes(bytes);
      XmlDocument document(String path) =>
          XmlDocument.parse(utf8.decode(zip.find(path)!.content));
      final workbook = document('xl/workbook.xml');
      expect(
        workbook.findAllElements('sheet').map((e) => e.getAttribute('name')),
        ['Income', 'Expense', 'Asset', 'Debt'],
      );
      final expense = document('xl/worksheets/sheet2.xml');
      final last = excelColumn(data.expenseColumns.length + 3);
      final total = expense
          .findAllElements('c')
          .firstWhere((e) => e.getAttribute('r') == 'C11');
      expect(total.getElement('f')!.innerText, 'SUM(D11:${last}11)');
      expect(total.getElement('v')!.innerText, '123');
      final asset = document('xl/worksheets/sheet3.xml');
      final name = asset
          .findAllElements('c')
          .firstWhere((e) => e.getAttribute('r') == 'D1');
      expect(name.getAttribute('t'), 'inlineStr');
      expect(name.innerText, '=SUM(1,2)&<合成>');
      expect(
        document('xl/styles.xml').toXmlString(),
        contains('formatCode="#,##0"'),
      );
      expect(
        asset.findAllElements('pane').single.getAttribute('topLeftCell'),
        'D2',
      );
      expect(excelColumn(26), 'Z');
      expect(excelColumn(27), 'AA');
      expect(excelColumn(16384), 'XFD');
      await Directory('.tooling/export-evidence').create(recursive: true);
      await File('.tooling/export-evidence/synthetic-jpy.xlsx')
          .writeAsBytes(bytes);
      final cny = financeXlsx(
        await exports.load('CNY', DateTime(2026), DateTime(2027)),
      );
      await File('.tooling/export-evidence/synthetic-cny.xlsx')
          .writeAsBytes(cny);
    },
  );

  test('empty categories and accounts yield valid zero totals with no invalid ranges', () async {
    await (db.delete(db.entries)).go();
    await (db.delete(db.accounts)).go();
    await (db.delete(db.categories)).go();
    final data = await exports.load(
      'CNY',
      DateTime(2026, 10),
      DateTime(2026, 11),
    );
    final zip = ZipDecoder().decodeBytes(financeXlsx(data));
    for (var i = 1; i <= 4; i++) {
      final xml = XmlDocument.parse(
        utf8.decode(zip.find('xl/worksheets/sheet$i.xml')!.content),
      );
      expect(xml.findAllElements('f').single.innerText, '0');
      expect(xml.findAllElements('v').last.innerText, '0.00');
    }
  });
}
