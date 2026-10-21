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
  fee('手续费', ['手续费', '转账手续费', 'fee']),
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
  String? defaultAccount, expenseCategory, incomeCategory, feeCategory;
  EntryKind defaultKind = EntryKind.expense;
  void detect(ImportTable table) {
    columns.clear();
    accounts.clear();
    categories.clear();
    kinds.clear();
    defaultAccount = expenseCategory = incomeCategory = feeCategory = null;
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

  bool get hasTransferAccounts =>
      columns.containsKey(ImportField.source) &&
      columns.containsKey(ImportField.target);

  bool hasFees(ImportTable table) => table.rows.any((row) {
    final text = value(row, ImportField.fee);
    return text.isNotEmpty && double.tryParse(text) != 0;
  });

  String? resolvedFeeCategory(List<Category> categories) =>
      feeCategory ??
      categories
          .where((c) => c.kind == 'expense' && c.name == '手续费')
          .firstOrNull
          ?.id ??
      categories
          .where((c) => c.kind == 'expense' && c.name == '其他损耗')
          .firstOrNull
          ?.id;

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
    bool duplicate = false,
    this.currency = 'CNY',
    this.fee,
  }) : principalDuplicate = duplicate;
  final int row, amount;
  final EntryKind kind;
  final String accountId, date, note;
  final String? categoryId, targetId;
  final bool principalDuplicate;
  final String currency;
  final ImportEntry? fee;

  bool get duplicate => principalDuplicate && (fee?.duplicate ?? true);
  bool get suspectedDuplicate =>
      principalDuplicate || (fee?.duplicate ?? false);

  // A partially imported row adds only its missing component. Explicitly
  // selecting a wholly duplicate row retains the existing override behavior.
  Iterable<ImportEntry> get recordsToImport sync* {
    if (!principalDuplicate || duplicate) yield this;
    if (fee != null && (!fee!.duplicate || duplicate)) yield fee!;
  }
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
          if (kind == null) {
            throw const FormatException('请关联交易类型；信贷账户还款可明确选择“转账”');
          }
          if (kind.isSettlement) {
            throw const FormatException('借贷还款需关联原借款，请在账本中记录或使用完整备份恢复');
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
          final rawFee = mapping.value(row, ImportField.fee);
          int fee;
          try {
            fee = rawFee.isEmpty ? 0 : parseMoney(rawFee, account.currency);
          } on FormatException {
            throw const FormatException('手续费须为有效的非负金额，且符合账户币种精度');
          }
          if (fee < 0 || fee > 999999999999) {
            throw const FormatException('手续费须为非负金额且不超出上限');
          }
          if (fee > 0 && kind != EntryKind.transfer) {
            throw const FormatException('手续费列仅适用于转账，请将收支手续费另记一行');
          }
          final feeCategory = mapping.resolvedFeeCategory(categories);
          if (fee > 0 &&
              !categories.any(
                (c) => c.id == feeCategory && c.kind == 'expense',
              )) {
            throw const FormatException('请选择手续费支出分类');
          }
          var feeNote = fee == 0
              ? ''
              : '转账手续费（${account.name} → ${target!.name}；转账 ${money(amount, account.currency)}）${note.isEmpty ? '' : '\n$note'}';
          if (feeNote.length > 2000) {
            var end = 2000;
            final unit = feeNote.codeUnitAt(end - 1);
            if (unit >= 0xd800 && unit <= 0xdbff) end--;
            feeNote = feeNote.substring(0, end);
          }
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
          final feeDuplicate =
              fee > 0 &&
              !seen.add(
                _signature(
                  EntryKind.expense.name,
                  fee,
                  account.id,
                  date,
                  feeNote,
                  feeCategory,
                  null,
                ),
              );
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
              fee: fee == 0
                  ? null
                  : ImportEntry(
                      row: i + 2,
                      kind: EntryKind.expense,
                      amount: fee,
                      accountId: account.id,
                      date: date,
                      note: feeNote,
                      categoryId: feeCategory,
                      duplicate: feeDuplicate,
                      currency: account.currency,
                    ),
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
      for (final entry in entries.expand((e) => e.recordsToImport)) {
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
