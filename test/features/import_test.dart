import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/importing/domain/import_table.dart';
import 'package:so_account/features/importing/domain/import_plan.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';

Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));
Uint8List workbook({bool formula = false}) {
  final zip = Archive();
  for (final entry in {
    'xl/workbook.xml': '<workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="明细" r:id="rId1"/></sheets></workbook>',
    'xl/_rels/workbook.xml.rels': '<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>',
    'xl/sharedStrings.xml': '<sst><si><t>日期</t></si><si><t>金额</t></si></sst>',
    'xl/worksheets/sheet1.xml':
        '<worksheet><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row><row r="2"><c r="A2"><v>46023</v></c><c r="B2">${formula ? '<f>1+2</f>' : ''}<v>12.50</v></c></row></sheetData></worksheet>',
  }.entries) {
    zip.addFile(ArchiveFile.string(entry.key, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(zip));
}

void main() {
  test('changing files resets previous mappings and defaults', () {
    final mapping = ImportMapping();
    mapping.defaultAccount = 'old';
    mapping.expenseCategory = 'old-category';
    mapping.accounts['钱包'] = 'old';
    mapping.detect(
      ImportTable.fromRows('new', [
        ['日期', '金额'],
        ['2026-01-01', '1'],
      ]),
    );
    expect(mapping.accounts, isEmpty);
    expect(mapping.defaultAccount, isNull);
    expect(mapping.expenseCategory, isNull);
  });
  test(
    'CSV parses BOM, quoted multiline cells, escaped quotes and semicolons',
    () {
      final table = readImportTables(
        'a.csv',
        bytes('\uFEFF日期,金额,说明\r\n2026-01-01,2.50,"第一行\n第二行,""好"""\r\n'),
      ).single;
      expect(table.headers, ['日期', '金额', '说明']);
      expect(table.rows.single.last, '第一行\n第二行,"好"');
      expect(
        readImportTables(
          'a.csv',
          bytes('日期;金额\n2026-01-01;2'),
        ).single.rows.single.last,
        '2',
      );
      expect(
        () => readImportTables('a.csv', bytes('日期,金额\n"未闭合,1')),
        throwsFormatException,
      );
    },
  );
  test(
    'Excel resolves shared strings and serial dates without executing formulas',
    () {
      final table = readImportTables('a.xlsx', workbook()).single;
      expect(table.name, '明细');
      expect(table.headers, ['日期', '金额']);
      expect(readImportTables('导出.xls', workbook()).single.headers, [
        '日期',
        '金额',
      ]);
      expect(importDate(table.rows.single.first), '2026-01-01');
      expect(
        () => readImportTables('a.xlsx', workbook(formula: true)),
        throwsFormatException,
      );
      expect(
        () => readImportTables('a.xls', bytes('legacy')),
        throwsFormatException,
      );
      expect(
        () => readImportTables('a.csv', Uint8List(maxImportBytes + 1)),
        throwsFormatException,
      );
    },
  );
  test('invalid dates reject overflow and mapped duplicate columns reject ambiguity', () {
    expect(() => importDate('2026-02-30'), throwsFormatException);
    expect(importDate('2026/1/2 12:30:45'), '2026-01-02');
    final table = ImportTable.fromRows('a', [
      ['日期', '金额'],
      ['2026-01-01', '1'],
    ]);
    final map = ImportMapping()..detect(table);
    map.columns[ImportField.amount] = 0;
    expect(() => previewImport(table, map, [], [], []), throwsFormatException);
  });

  late AppDatabase db;
  late List<Account> accounts;
  late List<Category> categories;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await LedgerRepository(db).saveAccount(
      name: '现金',
      kind: '资金账户',
      channel: '现金',
      currency: 'CNY',
      openingBalance: 0,
    );
    accounts = await db.select(db.accounts).get();
    categories = await db.select(db.categories).get();
  });
  tearDown(() => db.close());
  test(
    'real XLS maps, previews and commits exact dates and money to SQLite',
    () async {
      final table = readImportTables(
        '账单.xls',
        File('test/fixtures/import/ledger.xls').readAsBytesSync(),
      ).first;
      final mapping = ImportMapping()..detect(table);
      mapping.defaultAccount = accounts.single.id;
      final preview = previewImport(table, mapping, accounts, categories, []);
      expect(preview.map((r) => r.error), everyElement(isNull));
      expect(preview.map((r) => r.entry!.amount), [1250, 999]);
      expect(preview.first.entry!.date, '2026-10-20');
      expect(await commitImport(db, preview.map((r) => r.entry!).toList()), 2);
      final entries = await db.select(db.entries).get();
      expect(entries.map((e) => e.note), contains('午餐 🥒'));
      expect(
        (await LedgerRepository(db).watchBalances().first)[accounts.single.id],
        -251,
      );
    },
  );
  test(
    'account currency changed after preview rolls back the import',
    () async {
      await db.customStatement("UPDATE accounts SET currency = 'JPY'");
      final entry = ImportEntry(
        row: 2,
        kind: EntryKind.expense,
        amount: 100,
        accountId: accounts.single.id,
        date: '2026-01-01',
        note: '',
        categoryId: 'expense-0',
        currency: 'CNY',
      );
      await expectLater(commitImport(db, [entry]), throwsFormatException);
      expect(await db.select(db.entries).get(), isEmpty);
    },
  );

  test(
    'manual column and value mappings, errors and duplicates are previewed',
    () async {
      final table = ImportTable.fromRows('账单', [
        ['时间', '花了多少', '类别', '渠道', '收支'],
        ['2026-01-01', '-12.50', '吃饭', '钱包', '付款'],
        ['2026-01-01', '-12.50', '吃饭', '钱包', '付款'],
        ['错误', '2', '吃饭', '钱包', '付款'],
      ]);
      final mapping = ImportMapping()..detect(table);
      mapping.columns[ImportField.date] = 0;
      mapping.columns[ImportField.amount] = 1;
      mapping.columns[ImportField.account] = 3;
      mapping.kinds['付款'] = 'expense';
      mapping.accounts['钱包'] = accounts.single.id;
      mapping.categories['expense:吃饭'] = 'expense-3';
      final preview = previewImport(table, mapping, accounts, categories, []);
      expect(preview[0].entry!.amount, 1250);
      expect(preview[1].entry!.duplicate, isTrue);
      expect(preview[2].error, isNotNull);
      expect(await commitImport(db, [preview.first.entry!]), 1);
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
    },
  );
  test(
    'import is atomic when a previously valid account becomes unavailable',
    () async {
      final good = ImportEntry(
        row: 2,
        kind: EntryKind.expense,
        amount: 100,
        accountId: accounts.single.id,
        categoryId: 'expense-0',
        date: '2026-01-01',
        note: '',
      );
      final bad = ImportEntry(
        row: 3,
        kind: EntryKind.expense,
        amount: 100,
        accountId: 'missing',
        categoryId: 'expense-0',
        date: '2026-01-01',
        note: '',
      );
      await expectLater(commitImport(db, [good, bad]), throwsFormatException);
      expect(await db.select(db.entries).get(), isEmpty);
    },
  );
  test('currency mismatches and invalid transfers are errors, blank fields use defaults', () {
    final table = ImportTable.fromRows('a', [
      ['日期', '金额', '币种'],
      ['2026-01-01', '1', 'USD'],
      ['2026-01-02', '1', 'CNY'],
    ]);
    final mapping = ImportMapping()..detect(table);
    mapping.defaultAccount = accounts.single.id;
    mapping.expenseCategory = 'expense-0';
    final plan = previewImport(table, mapping, accounts, categories, []);
    expect(plan[0].error, contains('币种'));
    expect(plan[1].entry, isNotNull);
    mapping.defaultKind = EntryKind.transfer;
    expect(
      previewImport(table, mapping, accounts, categories, [])[1].error,
      isNotNull,
    );
  });
}
