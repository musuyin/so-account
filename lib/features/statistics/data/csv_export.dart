import 'package:drift/drift.dart';

import '../../../core/money/money.dart';
import '../../../core/time/business_date.dart';
import '../../../data/database/app_database.dart';
import '../../ledger/domain/entry_kind.dart';

enum ExportPeriod { all, month, year }

String csvCell(Object? value) {
  var text = value?.toString() ?? '';
  if (RegExp(r'^[\s\uFEFF]*[=+\-@\t\r]').hasMatch(text) ||
      text.startsWith('\t') ||
      text.startsWith('\r')) {
    text = "'$text";
  }
  return '"${text.replaceAll('"', '""')}"';
}

String csvDocument(List<List<Object?>> rows) =>
    '\uFEFF${rows.map((r) => r.map(csvCell).join(',')).join('\r\n')}\r\n';

class CsvExport {
  CsvExport(this.db);
  final AppDatabase db;
  Future<String> create(
    ExportPeriod period,
    DateTime date, {
    bool summary = false,
  }) async {
    if (summary && period == ExportPeriod.all) {
      throw const FormatException('汇总请选择月份或年份');
    }
    final start = period == ExportPeriod.month
        ? DateTime(date.year, date.month)
        : DateTime(date.year);
    final end = period == ExportPeriod.month
        ? DateTime(date.year, date.month + 1)
        : DateTime(date.year + 1);
    final clause = period == ExportPeriod.all
        ? ''
        : 'WHERE e.date >= ? AND e.date < ?';
    final variables = period == ExportPeriod.all
        ? <Variable>[]
        : [Variable(dateKey(start)), Variable(dateKey(end))];
    if (summary) {
      final rows = await db.customSelect('''
        SELECT a.currency, e.kind, COALESCE(c.name, '') AS category, SUM(e.amount) AS total, COUNT(*) AS count
        FROM entries e JOIN accounts a ON a.id = e.account_id LEFT JOIN categories c ON c.id = e.category_id
        $clause GROUP BY a.currency,e.kind,c.id,c.name ORDER BY a.currency,e.kind,total DESC
      ''', variables: variables).get();
      return csvDocument([
        ['期间', '币种', '类型', '分类', '金额', '笔数'],
        for (final r in rows)
          [
            period == ExportPeriod.month ? monthKey(date) : '${date.year}',
            r.read<String>('currency'),
            EntryKind.values.byName(r.read<String>('kind')).label,
            r.read<String>('category'),
            decimalMoney(r.read<int>('total'), r.read<String>('currency')),
            r.read<int>('count'),
          ],
      ]);
    }
    final rows = await db.customSelect('''
      SELECT e.*, a.name AS account_name, a.currency, t.name AS target_name, c.name AS category_name, d.name AS debt_name, d.channel AS debt_side
      FROM entries e JOIN accounts a ON a.id=e.account_id LEFT JOIN accounts t ON t.id=e.target_account_id
      LEFT JOIN categories c ON c.id=e.category_id LEFT JOIN accounts d ON d.id=e.debt_account_id $clause ORDER BY e.date,e.created_at
    ''', variables: variables).get();
    return csvDocument([
      [
        'ID',
        '日期',
        '类型',
        '币种',
        '金额',
        '账户',
        '转入账户',
        '分类',
        '关联借贷ID',
        '备注',
        '债务账户',
        '债务类别',
        '往来人',
      ],
      for (final r in rows)
        [
          r.read<String>('id'),
          r.read<String>('date'),
          EntryKind.values.byName(r.read<String>('kind')).label,
          r.read<String>('currency'),
          decimalMoney(r.read<int>('amount'), r.read<String>('currency')),
          r.read<String>('account_name'),
          r.readNullable<String>('target_name'),
          r.readNullable<String>('category_name'),
          r.readNullable<String>('debt_id'),
          r.read<String>('note'),
          r.readNullable<String>('debt_name'),
          r.readNullable<String>('debt_side'),
          r.read<String>('counterparty'),
        ],
    ]);
  }
}
