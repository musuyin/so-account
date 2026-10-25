import '../../../data/database/app_database.dart';
import '../../ledger/domain/entry_kind.dart';
import 'import_plan.dart';
import 'import_table.dart';

class MissingImportAccount {
  MissingImportAccount(this.name);
  final String name;
  final Set<String> currencies = {};
  final Set<int> rows = {};
  final Set<String> roles = {};
  String? firstDate;
  String? debtSide;
}

List<MissingImportAccount> missingImportDebtAccounts(
  ImportTable table,
  ImportMapping mapping,
  List<Account> accounts,
) {
  return importDebtAccountSources(table, mapping, accounts).where((source) {
    final side = source.debtSide!, currency = source.currencies.single;
    final id = mapping.debtAccounts['$side:$currency:${source.name}'];
    return accounts
        .where(
          (a) =>
              a.kind == '债务' &&
              a.currency == currency &&
              (a.channel == side || (side == '应收款' && a.channel == '报销')) &&
              (id != null ? a.id == id : a.name == source.name),
        )
        .isEmpty;
  }).toList();
}

List<MissingImportAccount> importDebtAccountSources(
  ImportTable table,
  ImportMapping mapping,
  List<Account> accounts,
) {
  final result = <String, MissingImportAccount>{};
  for (final (index, row) in table.rows.indexed) {
    final kind = mapping.kindFor(row);
    if (kind != EntryKind.borrow && kind != EntryKind.lend) continue;
    final side = kind == EntryKind.borrow ? '应付款' : '应收款';
    final source = mapping.sourceAccountValue(row, kind);
    final sourceId =
        mapping.accounts[source] ??
        (source.isEmpty ? mapping.defaultAccount : null);
    final fund = accounts
        .where(
          (a) =>
              a.kind != '债务' &&
              (sourceId != null ? a.id == sourceId : a.name == source),
        )
        .firstOrNull;
    if (fund == null) continue;
    var name = mapping.counterpartyValue(row, kind);
    if (name.isEmpty) name = '未注明往来人';
    final key = '$side:${fund.currency}:$name';
    final missing = result.putIfAbsent(
      key,
      () => MissingImportAccount(name)..debtSide = side,
    );
    missing.currencies.add(fund.currency);
    missing.roles.add(side);
    missing.rows.add(index + 2);
  }
  return result.values.toList();
}

List<MissingImportAccount> missingImportAccounts(
  ImportTable table,
  ImportMapping mapping,
  List<Account> accounts,
) {
  return importAccountSources(table, mapping).where((source) {
    final mapped = mapping.accounts[source.name];
    if (mapped != null &&
        accounts.any((a) => !a.isArchived && a.id == mapped)) {
      return false;
    }
    return !accounts.any(
      (a) =>
          !a.isArchived &&
          a.name == source.name &&
          (source.currencies.length != 1 ||
              source.currencies.contains(a.currency)),
    );
  }).toList();
}

List<MissingImportAccount> importAccountSources(
  ImportTable table,
  ImportMapping mapping,
) {
  final sources = <String, MissingImportAccount>{};
  for (var i = 0; i < table.rows.length; i++) {
    final row = table.rows[i];
    if (mapping.ignoredReason(row) != null) continue;
    final kind = mapping.kindFor(row);
    // Resolve the meaning before treating either side as a funds account.
    if (kind == null) continue;
    for (final (name, role) in [
      (
        mapping.sourceAccountValue(row, kind),
        kind == EntryKind.transfer
            ? '转账源账户'
            : [
                EntryKind.borrow,
                EntryKind.lend,
                EntryKind.repay,
                EntryKind.collect,
              ].contains(kind)
            ? '借贷资金账户'
            : '收支账户',
      ),
      if (kind == EntryKind.transfer)
        (mapping.value(row, ImportField.target), '转账目标账户'),
    ]) {
      if (name.isEmpty) continue;
      final source = sources.putIfAbsent(
        name,
        () => MissingImportAccount(name),
      );
      source.rows.add(i + 2);
      source.roles.add(role);
      final currency = mapping.value(row, ImportField.currency).toUpperCase();
      if (currency.isNotEmpty) source.currencies.add(currency);
      try {
        final date = importDate(mapping.value(row, ImportField.date));
        if (source.firstDate == null || date.compareTo(source.firstDate!) < 0) {
          source.firstDate = date;
        }
      } on FormatException {
        /* Row-level date errors remain in preview. */
      }
    }
  }
  return sources.values.toList();
}
