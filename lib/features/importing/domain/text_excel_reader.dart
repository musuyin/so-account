import 'dart:convert';
import 'dart:typed_data';

import 'package:html/parser.dart' as html;
import 'package:xml/xml.dart';

import 'xls_reader.dart';

/// Some exporters use .xls for SpreadsheetML 2003 or an HTML table.
List<XlsRows>? readTextExcelRows(Uint8List bytes) {
  final utf16 =
      bytes.length >= 2 &&
      ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
          (bytes[0] == 0xfe && bytes[1] == 0xff));
  if (!utf16 &&
      (bytes.isEmpty ||
          ![0x3c, 0xef, 0x20, 0x0d, 0x0a, 0x09].contains(bytes[0]))) {
    return null;
  }
  final String text;
  if (utf16) {
    if (bytes.length.isOdd) throw const FormatException('Excel 文本编码不完整');
    text = String.fromCharCodes([
      for (var i = 2; i < bytes.length; i += 2)
        bytes[0] == 0xff
            ? bytes[i] | bytes[i + 1] << 8
            : bytes[i] << 8 | bytes[i + 1],
    ]);
  } else {
    try {
      text = utf8.decode(bytes).replaceFirst('\uFEFF', '');
    } on FormatException {
      throw const FormatException(
        '此文本型 XLS 不是 UTF-8/UTF-16 编码，请用 Excel/WPS 另存为标准 .xlsx',
      );
    }
  }
  if (text.contains('urn:schemas-microsoft-com:office:spreadsheet')) {
    return _spreadsheetXml(text);
  }
  if (RegExp(r'<(?:html|table)\b', caseSensitive: false).hasMatch(text)) {
    return _htmlTables(text);
  }
  return null;
}

String? _attribute(XmlElement e, String name) =>
    e.attributes.where((a) => a.name.local == name).firstOrNull?.value;

List<XlsRows> _spreadsheetXml(String text) {
  final document = XmlDocument.parse(text);
  Iterable<XmlElement> elements(String name) => document.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == name);
  if (elements('Date1904').isNotEmpty) {
    throw const FormatException('暂不支持 1904 日期系统，请将日期列转为 YYYY-MM-DD 文本');
  }
  final result = <XlsRows>[];
  for (final sheet in elements('Worksheet')) {
    final rows = <List<String>>[];
    for (final row in sheet.descendants.whereType<XmlElement>().where(
      (e) => e.name.local == 'Row',
    )) {
      final values = <String>[];
      for (final cell in row.childElements.where(
        (e) => e.name.local == 'Cell',
      )) {
        if (_attribute(cell, 'Formula') != null) {
          throw const FormatException('Excel 含公式，请先粘贴为值再导入');
        }
        if ((_attribute(cell, 'MergeAcross') ?? '0') != '0' ||
            (_attribute(cell, 'MergeDown') ?? '0') != '0') {
          throw const FormatException('表格包含合并单元格，请整理为首行列名、每行一条明细');
        }
        final index =
            int.tryParse(_attribute(cell, 'Index') ?? '') ?? values.length + 1;
        if (index <= values.length || index > 100) {
          throw const FormatException('Excel 列位置无效或超过 100 列');
        }
        while (values.length < index) {
          values.add('');
        }
        final data = cell.childElements
            .where((e) => e.name.local == 'Data')
            .firstOrNull;
        if (data == null) continue;
        final type = _attribute(data, 'Type');
        if (type == 'Error') throw const FormatException('Excel 包含错误单元格');
        final value = data.innerText;
        values[index - 1] = type == 'DateTime' ? value.split('T').first : value;
      }
      if (values.any((v) => v.trim().isNotEmpty)) rows.add(values);
      if (rows.length > 10001) throw const FormatException('最多导入 10000 条明细');
    }
    if (rows.length >= 2) {
      result.add((name: _attribute(sheet, 'Name') ?? '工作表', rows: rows));
    }
    if (result.length > 64) throw const FormatException('工作表过多，最多支持 64 张');
  }
  if (result.isEmpty) throw const FormatException('Excel 没有可导入的工作表');
  return result;
}

List<XlsRows> _htmlTables(String text) {
  final document = html.parse(
    text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n'),
  );
  final result = <XlsRows>[];
  for (final table in document.querySelectorAll('table')) {
    final rows = <List<String>>[];
    for (final row in table.querySelectorAll('tr').where((r) {
      var parent = r.parent;
      while (parent != null && parent.localName != 'table') {
        parent = parent.parent;
      }
      return parent == table;
    })) {
      final cells = row.children.where(
        (c) => c.localName == 'td' || c.localName == 'th',
      );
      final values = <String>[];
      for (final cell in cells) {
        if (!['1', null].contains(cell.attributes['colspan']) ||
            !['1', null].contains(cell.attributes['rowspan'])) {
          throw const FormatException('表格包含合并单元格，请整理为首行列名、每行一条明细');
        }
        if (cell.attributes.containsKey('x:fmla')) {
          throw const FormatException('Excel 含公式，请先粘贴为值再导入');
        }
        values.add(cell.text.trim());
        if (values.length > 100) throw const FormatException('最多支持 100 列');
      }
      if (values.any((v) => v.isNotEmpty)) rows.add(values);
      if (rows.length > 10001) throw const FormatException('最多导入 10000 条明细');
    }
    if (rows.length >= 2) {
      result.add((name: '表格 ${result.length + 1}', rows: rows));
    }
    if (result.length > 64) throw const FormatException('工作表过多，最多支持 64 张');
  }
  if (result.isEmpty) throw const FormatException('Excel 没有可导入的表格');
  return result;
}
