import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/features/importing/domain/import_plan.dart';
import 'package:so_account/features/importing/domain/import_table.dart';

Uint8List fixture(String name) =>
    File('test/fixtures/import/$name.xls').readAsBytesSync();
Uint8List textBytes(String text) => Uint8List.fromList(utf8.encode(text));
Matcher message(String text) => throwsA(
  isA<FormatException>().having((e) => e.message, 'message', contains(text)),
);

void main() {
  for (final file in ['ledger', 'mini-stream']) {
    test(
      'reads independently generated XLS $file: sheets, Chinese, emoji, numbers, date',
      () {
        final tables = readImportTables('$file.XLS', fixture(file));
        expect(tables.map((t) => t.name), ['日常明细', '备用明细']);
        expect(tables.first.headers, ['日期', '金额', '账户', '分类', '类型', '备注']);
        expect(importDate(tables.first.rows[0][0]), '2026-10-20');
        expect(tables.first.rows[0].sublist(1), [
          '12.5',
          '现金',
          '普通餐饮',
          '支出',
          '午餐 🥒',
        ]);
        expect(tables.first.rows[1], [
          '2026-10-19',
          '-9.99',
          '',
          '工资',
          '收入',
          '补记',
        ]);
        expect(tables[1].rows.single, ['2026-10-18', '0.1']);
        final mapping = ImportMapping()..detect(tables.first);
        expect(mapping.columns[ImportField.date], 0);
        expect(mapping.columns[ImportField.amount], 1);
      },
    );
  }
  test('SST CONTINUE boundaries preserve all mixed-width shared strings and a long cell', () {
    final table = readImportTables('账单.xls', fixture('shared-strings')).single;
    expect(table.rows.length, 1201);
    for (var i = 0; i < 1200; i++) {
      expect(table.rows[i][2], '第${i + 1}条中文备注-ASCII-🥒');
      expect(double.parse(table.rows[i][1]), (i + 1) / 100);
    }
    expect(table.rows.last[2], '长' * 8500);
  });
  test('rejects formulas and 1904 dates explicitly', () {
    expect(() => readImportTables('a.xls', fixture('formula')), message('含公式'));
    expect(
      () => readImportTables('a.xls', fixture('date1904')),
      message('1904'),
    );
  });
  test('truncated XLS and invalid SST index never silently lose values', () {
    final bytes = fixture('ledger');
    expect(
      () => readImportTables('a.xls', bytes.sublist(0, bytes.length - 1)),
      message('损坏'),
    );
    final changed = Uint8List.fromList(bytes);
    // The Workbook stream of this independently generated CFB begins at sector 0.
    var found = false;
    for (var i = 512; i + 14 < changed.length; i++) {
      if (changed[i] == 0xfd &&
          changed[i + 1] == 0 &&
          changed[i + 2] == 10 &&
          changed[i + 3] == 0) {
        ByteData.sublistView(changed)
            .setUint32(i + 10, 0xffffff, Endian.little);
        found = true;
        break;
      }
    }
    expect(found, isTrue);
    expect(() => readImportTables('a.xls', changed), message('损坏'));
  });
  test('cyclic FAT chain fails without looping', () {
    final bytes = fixture('ledger');
    final view = ByteData.sublistView(bytes);
    final fat = view.getUint32(76, Endian.little);
    view.setUint32(
      (fat + 1) * 512,
      0,
      Endian.little,
    ); // sector zero points to itself
    expect(() => readImportTables('a.xls', bytes), message('损坏'));
  });
  test('rejects oversized column coordinate before allocating row', () {
    final bytes = fixture('ledger');
    for (var i = 512; i + 14 < bytes.length; i++) {
      if (bytes[i] == 0xfd &&
          bytes[i + 1] == 0 &&
          bytes[i + 2] == 10 &&
          bytes[i + 3] == 0) {
        ByteData.sublistView(bytes).setUint16(i + 6, 255, Endian.little);
        break;
      }
    }
    expect(() => readImportTables('a.xls', bytes), message('100 列'));
  });
  test('invalid CFB geometry is rejected', () {
    final bytes = fixture('ledger');
    ByteData.sublistView(bytes).setUint16(30, 31, Endian.little);
    expect(() => readImportTables('a.xls', bytes), message('损坏'));
  });
  test('encrypted XLS is explained before attempting to read transactions', () {
    final bytes = fixture('ledger');
    final view = ByteData.sublistView(bytes);
    final secondRecord = 512 + 4 + view.getUint16(514, Endian.little);
    view.setUint16(secondRecord, 0x002f, Endian.little);
    expect(() => readImportTables('a.xls', bytes), message('已加密'));
  });
  test(
    'Excel error cells are rejected instead of becoming missing amounts',
    () {
      final bytes = fixture('ledger');
      for (var i = 512; i + 14 < bytes.length; i++) {
        if (bytes[i] == 0xfd &&
            bytes[i + 1] == 0 &&
            bytes[i + 2] == 10 &&
            bytes[i + 3] == 0) {
          ByteData.sublistView(bytes).setUint16(i, 0x0205, Endian.little);
          bytes[i + 11] = 1;
          break;
        }
      }
      expect(() => readImportTables('a.xls', bytes), message('错误单元格'));
    },
  );
  test('cyclic MiniFAT is rejected without blocking the worker', () {
    final bytes = fixture('mini-stream');
    final view = ByteData.sublistView(bytes);
    final miniFatSector = view.getUint32(60, Endian.little);
    view.setUint32((miniFatSector + 1) * 512, 0, Endian.little);
    expect(() => readImportTables('a.xls', bytes), message('损坏'));
  });

  const xml = '''<?xml version="1.0"?>
<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
<Worksheet ss:Name="XML明细"><Table>
<Row><Cell><Data ss:Type="String">日期</Data></Cell><Cell><Data ss:Type="String">金额</Data></Cell><Cell><Data ss:Type="String">备注</Data></Cell></Row>
<Row><Cell><Data ss:Type="DateTime">2026-10-20T12:00:00.000</Data></Cell><Cell><Data ss:Type="Number">12.50</Data></Cell><Cell><Data ss:Type="String">午餐 &amp; 饮料</Data></Cell></Row>
<Row><Cell><Data ss:Type="String">2026-10-19</Data></Cell><Cell ss:Index="3"><Data ss:Type="String">缺金额</Data></Cell></Row>
</Table></Worksheet></Workbook>''';
  test('SpreadsheetML .xls preserves names, sparse columns and dates', () {
    final table = readImportTables('导出.xls', textBytes(xml)).single;
    expect(table.name, 'XML明细');
    expect(table.rows[0], ['2026-10-20', '12.50', '午餐 & 饮料']);
    expect(table.rows[1], ['2026-10-19', '', '缺金额']);
  });
  test('UTF16 BOM SpreadsheetML is supported', () {
    for (final little in [true, false]) {
      final bytes = Uint8List(xml.length * 2 + 2),
          view = ByteData.sublistView(Uint8List(xml.length * 2 + 2));
      view.setUint16(0, 0xfeff, little ? Endian.little : Endian.big);
      for (var i = 0; i < xml.length; i++) {
        view.setUint16(
          2 + i * 2,
          xml.codeUnitAt(i),
          little ? Endian.little : Endian.big,
        );
      }
      bytes.setAll(0, view.buffer.asUint8List());
      expect(readImportTables('导出.xls', bytes).single.rows.first[2], '午餐 & 饮料');
    }
  });
  test(
    'SpreadsheetML formula, merged cells and invalid width are actionable',
    () {
      expect(
        () => readImportTables(
          'a.xls',
          textBytes(xml.replaceFirst('<Cell>', '<Cell ss:Formula="=1+2">')),
        ),
        message('含公式'),
      );
      expect(
        () => readImportTables(
          'a.xls',
          textBytes(xml.replaceFirst('<Cell>', '<Cell ss:MergeAcross="2">')),
        ),
        message('合并单元格'),
      );
      expect(
        () => readImportTables(
          'a.xls',
          textBytes(xml.replaceFirst('ss:Index="3"', 'ss:Index="101"')),
        ),
        message('100 列'),
      );
    },
  );
  test('HTML exported as XLS handles entities and line breaks without executing scripts', () {
    final table = readImportTables(
      '网页账单.xls',
      textBytes('''<html><body><table>
<tr><th>日期<th>金额<th>备注
<tr><td>2026-10-20<td>12.50<td>午餐 &amp; 饮料<br>第二行
</table><script>throw new Error('never executed')</script></body></html>'''),
    ).single;
    expect(table.headers, ['日期', '金额', '备注']);
    expect(table.rows.single, ['2026-10-20', '12.50', '午餐 & 饮料\n第二行']);
  });
  test('unsupported text encoding and empty files explain the reason', () {
    expect(
      () => readImportTables(
        'a.xls',
        Uint8List.fromList([60, 104, 116, 109, 108, 62, 0xd6, 0xd0]),
      ),
      message('编码'),
    );
    expect(() => readImportTables('a.xls', Uint8List(0)), message('为空'));
  });
  test(
    'background decoder accepts XLS data without any widget references',
    () async {
      final tables = await readImportTablesInBackground(
        'a.xls',
        fixture('ledger'),
      );
      expect(tables.first.rows.first.last, '午餐 🥒');
    },
  );
}
