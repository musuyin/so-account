import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../../core/money/money.dart';
import 'finance_export.dart';

const _ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _relations =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _declaration = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';

String _text(String value) =>
    XmlText(value.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), ''))
        .toXmlString();

String excelColumn(int index) {
  var result = '';
  for (var n = index; n > 0; n = (n - 1) ~/ 26) {
    result = String.fromCharCode(65 + (n - 1) % 26) + result;
  }
  return result;
}

/// A native OOXML export. Text is always inlineStr, never an executable formula.
/// SUM totals carry cached results for viewers that do not recalculate on open.
Uint8List financeXlsx(FinanceExportData data) {
  final archive = Archive();
  void file(String path, String xml) =>
      archive.addFile(ArchiveFile.string(path, '$_declaration$xml'));
  final definitions = [
    ('Income', '总收入', data.incomeColumns, (FinanceMonth m) => m.income),
    ('Expense', '总支出', data.expenseColumns, (FinanceMonth m) => m.expense),
    ('Asset', '总资产', data.assetColumns, (FinanceMonth m) => m.assets),
    ('Debt', '总负债', data.debtColumns, (FinanceMonth m) => m.debt),
  ];
  file('[Content_Types].xml', '''
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
      <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
      ${[for (var i = 1; i <= 4; i++) '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}
    </Types>''');
  file(
    '_rels/.rels',
    '''<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="$_relations/officeDocument" Target="xl/workbook.xml"/>
  </Relationships>''',
  );
  file('xl/workbook.xml', '''<workbook xmlns="$_ns" xmlns:r="$_relations">
    <bookViews><workbookView activeTab="0"/></bookViews><sheets>
    ${[for (var i = 0; i < 4; i++) '<sheet name="${definitions[i].$1}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}
    </sheets><calcPr calcId="191029" fullCalcOnLoad="1"/></workbook>''');
  file(
    'xl/_rels/workbook.xml.rels',
    '''<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    ${[for (var i = 1; i <= 4; i++) '<Relationship Id="rId$i" Type="$_relations/worksheet" Target="worksheets/sheet$i.xml"/>'].join()}
    <Relationship Id="rId5" Type="$_relations/styles" Target="styles.xml"/>
  </Relationships>''',
  );
  final numberFormat = fractionDigits(data.currency) == 0
      ? '#,##0'
      : '#,##0.00';
  file('xl/styles.xml', '''<styleSheet xmlns="$_ns">
    <numFmts count="2"><numFmt numFmtId="164" formatCode="$numberFormat"/><numFmt numFmtId="165" formatCode="yyyy-mm"/></numFmts>
    <fonts count="3"><font><sz val="11"/><name val="Noto Sans SC"/><color rgb="FF202824"/></font><font><b/><sz val="11"/><name val="Noto Sans SC"/><color rgb="FFFFFFFF"/></font><font><b/><sz val="11"/><name val="Noto Sans SC"/><color rgb="FF202824"/></font></fonts>
    <fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF285541"/><bgColor indexed="64"/></patternFill></fill></fills>
    <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
    <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
    <cellXfs count="6">
      <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"><alignment vertical="center"/></xf>
      <xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>
      <xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"><alignment vertical="center"/></xf>
      <xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"><alignment vertical="center"/></xf>
      <xf numFmtId="164" fontId="2" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"><alignment vertical="center"/></xf>
      <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
    </cellXfs>
    <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
  </styleSheet>''');
  for (var sheetIndex = 0; sheetIndex < definitions.length; sheetIndex++) {
    final definition = definitions[sheetIndex], columns = definition.$3;
    if (columns.length > 16381 || data.months.length > 1048570) {
      throw const FormatException('数据超出 Excel 工作表容量，请缩小范围');
    }
    final last = excelColumn(columns.length + 3);
    final rows = StringBuffer();
    String cell(String ref, String value, int style) =>
        '<c r="$ref" s="$style" t="inlineStr"><is><t xml:space="preserve">${_text(value)}</t></is></c>';
    final headers = ['编号', '时间', definition.$2, ...columns.map((c) => c.name)];
    final longest = headers.fold<int>(
      0,
      (n, h) => h.runes.length > n ? h.runes.length : n,
    );
    final headerHeight = (((longest + 11) ~/ 12) * 16).clamp(48, 180);
    rows.write('<row r="1" ht="$headerHeight" customHeight="1">');
    for (var c = 0; c < headers.length; c++) {
      rows.write(cell('${excelColumn(c + 1)}1', headers[c], 1));
    }
    rows.write('</row>');
    for (var i = 0; i < data.months.length; i++) {
      final month = data.months[i], row = i + 2;
      final values = definition.$4(month);
      final serial = DateTime.utc(
        month.date.year,
        month.date.month,
      ).difference(DateTime.utc(1899, 12, 30)).inDays;
      rows.write(
        '<row r="$row" ht="24" customHeight="1"><c r="A$row"><v>$i</v></c><c r="B$row" s="2"><v>$serial</v></c>',
      );
      final formula = columns.isEmpty ? '0' : 'SUM(D$row:$last$row)';
      rows.write(
        '<c r="C$row" s="4"><f>$formula</f><v>${decimalMoney(month.total(values), data.currency)}</v></c>',
      );
      for (var c = 0; c < columns.length; c++) {
        rows.write(
          '<c r="${excelColumn(c + 4)}$row" s="3"><v>${decimalMoney(values[columns[c].id] ?? 0, data.currency)}</v></c>',
        );
      }
      rows.write('</row>');
    }
    final noteRow = data.months.length + 4;
    final noteColumns = columns.length.clamp(0, 5);
    final noteLast = excelColumn(noteColumns + 3);
    final note = '币种：${data.currency}。$financeExportBasis';
    final charsPerLine = ((42 + noteColumns * 26) ~/ 2).clamp(20, 160);
    final noteHeight =
        (((note.runes.length + charsPerLine - 1) ~/ charsPerLine) * 18).clamp(
          54,
          360,
        );
    rows.write(
      '<row r="$noteRow" ht="$noteHeight" customHeight="1">${cell('A$noteRow', note, 5)}</row>',
    );
    file('xl/worksheets/sheet${sheetIndex + 1}.xml', '''<worksheet xmlns="$_ns">
      <dimension ref="A1:$last$noteRow"/>
      <sheetViews><sheetView workbookViewId="0" showGridLines="0"><pane xSplit="3" ySplit="1" topLeftCell="D2" activePane="bottomRight" state="frozen"/><selection pane="bottomRight" activeCell="D2" sqref="D2"/></sheetView></sheetViews>
      <sheetFormatPr defaultRowHeight="24"/>
      <cols><col min="1" max="1" width="8" customWidth="1"/><col min="2" max="2" width="14" customWidth="1"/><col min="3" max="3" width="20" customWidth="1"/>${columns.isEmpty ? '' : '<col min="4" max="${columns.length + 3}" width="26" customWidth="1"/>'}</cols>
      <sheetData>$rows</sheetData><autoFilter ref="A1:$last${data.months.length + 1}"/>
      <mergeCells count="1"><mergeCell ref="A$noteRow:$noteLast$noteRow"/></mergeCells>
    </worksheet>''');
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
