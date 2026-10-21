import '../../../core/money/money.dart';
import '../../../core/time/business_date.dart';
import '../../../data/database/app_database.dart';
import '../../ledger/data/ledger_repository.dart';
import '../../ledger/domain/entry_kind.dart';
import 'import_table.dart';

enum ImportField {
  date('日期', ['日期', '交易时间', '发生日期', 'date']),
  kind('交易类型', ['收支类型', '交易类型', '类型', '收支', '收/支', 'type']),
  amount('金额', ['金额', '交易金额', 'amount']),
  account('收支账户', ['账户', '收支账户', '支付方式', 'account']),
  source('源账户', [
    '源账户',
    '转出账户',
    '来源账户',
    'source_account',
    'source account',
    'from_account',
  ]),
  target('目标账户', [
    '目标账户',
    '转入账户',
    'target_account',
    'target account',
    'to_account',
  ]),
  category('分类', ['分类', '类别', '交易分类', 'category']),
  currency('币种', ['币种', 'currency']),
  note('备注', ['备注', '说明', '商品', 'note']);

  const ImportField(this.label, this.aliases);
  final String label;
  final List<String> aliases;
}

class ImportMapping {
  final Map<ImportField, int> columns = {};
  final Map<String, String> accounts = {}, categories = {}, kinds = {};
  String? defaultAccount, expenseCategory, incomeCategory;
  EntryKind defaultKind = EntryKind.expense;
  void detect(ImportTable table) {
    columns.clear();
    accounts.clear();
    categories.clear();
    kinds.clear();
    defaultAccount = expenseCategory = incomeCategory = null;
    defaultKind = EntryKind.expense;
    for (final field in ImportField.values) {
      int index = -1;
      for (final alias in field.aliases) {
        index = table.headers.indexWhere(
          (h) => h.toLowerCase().trim() == alias,
        );
        if (index >= 0) break;
      }
      if (index >= 0) columns[field] = index;
    }
  }

  String value(List<String> row, ImportField field) {
    final index = columns[field];
    return index == null || index >= row.length ? '' : row[index].trim();
  }

  EntryKind? kindFor(List<String> row) {
    final source = value(row, ImportField.kind);
    return source.isEmpty ? defaultKind : detectedKind(kinds[source] ?? source);
  }

  // Original templates use one account column for ordinary income/expense.
  // Transfers prefer their explicit source; legacy account-as-source still works.
  String sourceAccountValue(List<String> row, EntryKind? kind) {
    final ordinary = value(row, ImportField.account);
    final source = value(row, ImportField.source);
    return kind == EntryKind.transfer
        ? (source.isNotEmpty ? source : ordinary)
        : (ordinary.isNotEmpty ? ordinary : source);
  }
}

String importDate(String value) {
  final serial = double.tryParse(value);
  if (serial != null && serial >= 61 && serial < 2958466) {
    return dateKey(DateTime(1899, 12, 30).add(Duration(days: serial.floor())));
  }
  final match = RegExp(
    r'^(\d{4})[-/年](\d{1,2})[-/月](\d{1,2})日?(?:[ T]\d{1,2}:\d{2}(?::\d{2}(?:\.\d+)?)?)?$',
  ).firstMatch(value);
  if (match == null) throw const FormatException('日期格式应为 YYYY-MM-DD');
  final date =
      '${match[1]}-${match[2]!.padLeft(2, '0')}-${match[3]!.padLeft(2, '0')}';
  parseDate(date);
  return date;
}

EntryKind? detectedKind(String value) => EntryKind.values
    .where(
      (k) =>
          k.label == value.replaceAll('帐', '账').trim() ||
          k.name == value.toLowerCase().trim(),
    )
    .firstOrNull;

class ImportEntry {
  const ImportEntry({
    required this.row,
    required this.kind,
    required this.amount,
    required this.accountId,
    required this.date,
    required this.note,
    this.categoryId,
    this.targetId,
    this.duplicate = false,
    this.currency = 'CNY',
  });
  final int row, amount;
  final EntryKind kind;
  final String accountId, date, note;
  final String? categoryId, targetId;
  final bool duplicate;
  final String currency;
}

class ImportResult {
  ImportResult(this.row, this.entry, this.error);
  final int row;
  final ImportEntry? entry;
  final String? error;
}

String _signature(
  String kind,
  int amount,
  String account,
  String date,
  String note,
  String? category,
  String? target,
) => [
  kind,
  '$amount',
  account,
  date,
  note,
  category ?? '',
  target ?? '',
].map((v) => '${v.length}:$v').join();

List<ImportResult> previewImport(
  ImportTable table,
  ImportMapping mapping,
  List<Account> accounts,
  List<Category> categories,
  List<Entry> existing,
) {
  if (!mapping.columns.containsKey(ImportField.date) ||
      !mapping.columns.containsKey(ImportField.amount)) {
    throw const FormatException('请关联日期和金额列');
  }
  if (mapping.columns.values.toSet().length != mapping.columns.length) {
    throw const FormatException('每一列只能关联一个字段');
  }
  final seen = {
    for (final e in existing)
      _signature(
        e.kind,
        e.amount,
        e.accountId,
        e.date,
        e.note,
        e.categoryId,
        e.targetAccountId,
      ),
  };
  return [
    for (var i = 0; i < table.rows.length; i++)
      (() {
        try {
          final row = table.rows[i];
          final kind = mapping.kindFor(row);
          if (kind == null || kind.isSettlement) {
            throw const FormatException('请映射交易类型；借贷还款请使用完整备份恢复');
          }
          Account resolveAccount(String value, {bool target = false}) {
            final id = value.isEmpty
                ? (target ? null : mapping.defaultAccount)
                : mapping.accounts[value];
            final matches = accounts
                .where((a) => id != null ? a.id == id : a.name == value)
                .toList();
            if (matches.length != 1) {
              throw FormatException(
                '请关联${target
                    ? '目标账户'
                    : kind == EntryKind.transfer
                    ? '源账户'
                    : '收支账户'}：$value',
              );
            }
            return matches.single;
          }

          final account = resolveAccount(mapping.sourceAccountValue(row, kind));
          final currency = mapping
              .value(row, ImportField.currency)
              .toUpperCase();
          if (currency.isNotEmpty && currency != account.currency) {
            throw const FormatException('币种与账户不一致');
          }
          final rawAmount = mapping.value(row, ImportField.amount);
          if (rawAmount.contains(',') &&
              !RegExp(r'^-?\d{1,3}(,\d{3})+(\.\d+)?$').hasMatch(rawAmount)) {
            throw const FormatException('金额千分位格式无效');
          }
          final amount = parseMoney(
            rawAmount.replaceAll(',', ''),
            account.currency,
            signed: true,
          ).abs();
          if (amount == 0 || amount > 999999999999) {
            throw const FormatException('金额须大于零且不超出上限');
          }
          String? categoryId;
          if (kind.needsCategory) {
            final value = mapping.value(row, ImportField.category);
            final id =
                mapping.categories['${kind.name}:$value'] ??
                (value.isEmpty
                    ? (kind == EntryKind.expense
                          ? mapping.expenseCategory
                          : mapping.incomeCategory)
                    : null);
            final matches = categories
                .where(
                  (c) =>
                      c.kind == kind.name &&
                      (id != null ? c.id == id : c.name == value),
                )
                .toList();
            if (matches.length != 1) {
              throw FormatException('请关联${kind.label}分类：$value');
            }
            categoryId = matches.single.id;
          }
          if (kind == EntryKind.transfer &&
              !mapping.columns.containsKey(ImportField.target)) {
            throw const FormatException('转账需要目标账户列，请先关联列名');
          }
          if (kind == EntryKind.transfer &&
              mapping.value(row, ImportField.target).isEmpty) {
            throw const FormatException('转账缺少目标账户，请填写后导入');
          }
          final target = kind == EntryKind.transfer
              ? resolveAccount(
                  mapping.value(row, ImportField.target),
                  target: true,
                )
              : null;
          if (target != null &&
              (target.id == account.id ||
                  target.currency != account.currency)) {
            throw const FormatException('目标账户须为另一个同币种账户');
          }
          final date = importDate(mapping.value(row, ImportField.date));
          final note = mapping.value(row, ImportField.note);
          if (note.length > 2000) throw const FormatException('备注不能超过 2000 字');
          final signature = _signature(
            kind.name,
            amount,
            account.id,
            date,
            note,
            categoryId,
            target?.id,
          );
          final duplicate = !seen.add(signature);
          return ImportResult(
            i + 2,
            ImportEntry(
              row: i + 2,
              kind: kind,
              amount: amount,
              accountId: account.id,
              date: date,
              note: note,
              categoryId: categoryId,
              targetId: target?.id,
              duplicate: duplicate,
              currency: account.currency,
            ),
            null,
          );
        } on FormatException catch (e) {
          return ImportResult(i + 2, null, e.message.toString());
        }
      })(),
  ];
}

Future<int> commitImport(AppDatabase db, List<ImportEntry> entries) =>
    db.transaction(() async {
      if (entries.isEmpty) throw const FormatException('请至少选择一条明细');
      final ledger = LedgerRepository(db);
      final accounts = {
        for (final account in await db.select(db.accounts).get())
          account.id: account,
      };
      for (final entry in entries) {
        if (accounts[entry.accountId]?.currency != entry.currency) {
          throw const FormatException('账户币种已变化或账户已删除，请重新预览');
        }
        await ledger.saveEntry(
          kind: entry.kind,
          amount: entry.amount,
          accountId: entry.accountId,
          categoryId: entry.categoryId,
          targetAccountId: entry.targetId,
          date: entry.date,
          note: entry.note,
        );
      }
      return entries.length;
    });
