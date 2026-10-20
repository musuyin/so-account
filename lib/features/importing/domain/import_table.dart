import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

const maxImportBytes = 10 * 1024 * 1024;
const maxImportRows = 10000;

// Keep this closure outside widget methods so only file data crosses isolates.
Future<List<ImportTable>> readImportTablesInBackground(
  String filename,
  Uint8List bytes,
) => Isolate.run(() => readImportTables(filename, bytes));

class ImportTable {
  ImportTable(this.name, this.headers, this.rows);
  final String name;
  final List<String> headers;
  final List<List<String>> rows;
  factory ImportTable.fromRows(String name, List<List<String>> input) {
    if (input.length < 2 ||
        input.length > maxImportRows + 1 ||
        input.first.length > 100) {
      throw const FormatException('需要表头和明细，最多 10000 条、100 列');
    }
    final headers = [
      for (var i = 0; i < input.first.length; i++)
        input.first[i].trim().isEmpty ? '未命名列 ${i + 1}' : input.first[i].trim(),
    ];
    final rows = input
        .skip(1)
        .where((r) => r.any((c) => c.trim().isNotEmpty))
        .toList();
    if (rows.isEmpty) throw const FormatException('没有可导入的明细');
    if (rows.any(
      (r) => r.length > headers.length || r.any((c) => c.length > 10000),
    )) {
      throw const FormatException('数据列数超过表头，或单元格过长');
    }
    return ImportTable(name, headers, rows);
  }
}

List<ImportTable> readImportTables(String filename, Uint8List bytes) {
  if (bytes.length > maxImportBytes) {
    throw const FormatException('文件不能超过 10 MB');
  }
  try {
    if (filename.toLowerCase().endsWith('.csv')) {
      var text = utf8.decode(bytes).replaceFirst(RegExp(r'^\uFEFF'), '');
      // Explicit UTF-8 avoids silently corrupting account and category names.
      final separators = {',': 0, ';': 0};
      var inHeaderQuote = false;
      for (final c in text.split(RegExp(r'[\r\n]')).first.split('')) {
        if (c == '"') {
          inHeaderQuote = !inHeaderQuote;
        }
        if (!inHeaderQuote && separators.containsKey(c)) {
          separators[c] = separators[c]! + 1;
        }
      }
      final delimiter = separators[',']! >= separators[';']! ? ',' : ';';
      final rows = <List<String>>[];
      var row = <String>[], field = StringBuffer();
      var quoted = false, closed = false;
      for (var i = 0; i < text.length; i++) {
        if (row.length > 100 || field.length > 10000) {
          throw const FormatException('最多 100 列，单元格最多 10000 字');
        }
        final c = text[i];
        if (quoted) {
          if (c == '"') {
            if (i + 1 < text.length && text[i + 1] == '"') {
              field.write('"');
              i++;
            } else {
              quoted = false;
              closed = true;
            }
          } else {
            field.write(c);
          }
        } else if (c == delimiter || c == '\n' || c == '\r') {
          row.add(field.toString());
          field = StringBuffer();
          closed = false;
          if (c != delimiter) {
            rows.add(row);
            if (rows.length > maxImportRows + 1) {
              throw const FormatException('最多导入 10000 条明细');
            }
            row = [];
            if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
          }
        } else if (c == '"' && field.isEmpty && !closed) {
          quoted = true;
        } else {
          if (closed || c == '"') throw const FormatException('CSV 引号格式错误');
          field.write(c);
        }
      }
      if (quoted) throw const FormatException('CSV 引号未闭合');
      if (field.isNotEmpty || row.isNotEmpty || closed) {
        row.add(field.toString());
        rows.add(row);
      }
      return [ImportTable.fromRows(filename, rows)];
    }
    if (!filename.toLowerCase().endsWith('.xlsx')) {
      throw const FormatException('请选择 CSV 或 Excel .xlsx，旧版 .xls 请另存为 .xlsx');
    }
    final directory = ZipDirectory()..read(InputMemoryStream(bytes));
    if (directory.fileHeaders.length > 2000 ||
        directory.fileHeaders.fold<int>(
              0,
              (n, h) => n + (h.file?.uncompressedSize ?? maxImportBytes * 10),
            ) >
            40 * 1024 * 1024) {
      throw const FormatException('Excel 解压体积过大');
    }
    final zip = ZipDecoder().decodeBytes(bytes, verify: true);
    XmlDocument document(String path) {
      final file = zip.findFile(path);
      if (file == null) throw const FormatException('Excel 缺少工作表结构');
      return XmlDocument.parse(utf8.decode(file.content));
    }

    final strings = zip.findFile('xl/sharedStrings.xml') == null
        ? <String>[]
        : document('xl/sharedStrings.xml')
              .findAllElements('si')
              .map(
                (si) => si.findAllElements('t').map((e) => e.innerText).join(),
              )
              .toList();
    final relationships = {
      for (final r in document(
        'xl/_rels/workbook.xml.rels',
      ).findAllElements('Relationship'))
        r.getAttribute('Id'): r.getAttribute('Target')!,
    };
    final workbook = document('xl/workbook.xml');
    if (workbook
        .findAllElements('workbookPr')
        .any((p) => ['1', 'true'].contains(p.getAttribute('date1904')))) {
      throw const FormatException('暂不支持 1904 日期系统，请将日期列转为 YYYY-MM-DD 文本');
    }
    final tables = <ImportTable>[];
    for (final sheet in workbook.findAllElements('sheet')) {
      final id = sheet.attributes
          .where((a) => a.name.local == 'id')
          .firstOrNull
          ?.value;
      final target = relationships[id];
      if (target == null || target.contains('..') || target.contains('://')) {
        throw const FormatException('Excel 工作表路径无效');
      }
      final path = target.startsWith('/') ? target.substring(1) : 'xl/$target';
      final rows = <List<String>>[];
      for (final element in document(path).findAllElements('row')) {
        if (rows.length > maxImportRows) {
          throw const FormatException('最多导入 10000 条明细');
        }
        final row = <String>[];
        for (final cell in element.findElements('c')) {
          final ref = cell.getAttribute('r') ?? '';
          final letters = RegExp(r'^[A-Z]+').stringMatch(ref);
          if (letters == null) throw const FormatException('Excel 单元格位置无效');
          var index = 0;
          for (final letter in letters.codeUnits) {
            index = index * 26 + letter - 64;
          }
          if (index > 100) throw const FormatException('最多支持 100 列');
          while (row.length < index) {
            row.add('');
          }
          if (cell.findElements('f').isNotEmpty) {
            throw const FormatException('Excel 含公式，请先粘贴为值再导入');
          }
          var value = cell.findElements('v').firstOrNull?.innerText ?? '';
          if (cell.getAttribute('t') == 's') {
            value = strings[int.parse(value)];
          }
          if (cell.getAttribute('t') == 'inlineStr') {
            value = cell.findAllElements('t').map((e) => e.innerText).join();
          }
          if (cell.getAttribute('t') == 'e') {
            throw const FormatException('Excel 包含错误单元格');
          }
          row[index - 1] = value;
        }
        if (row.any((v) => v.trim().isNotEmpty)) rows.add(row);
      }
      if (rows.length >= 2) {
        tables.add(
          ImportTable.fromRows(sheet.getAttribute('name') ?? '工作表', rows),
        );
      }
    }
    if (tables.isEmpty) throw const FormatException('Excel 没有可导入的工作表');
    return tables;
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('文件无法读取；CSV 请使用 UTF-8 编码，Excel 请使用标准 .xlsx');
  }
}
