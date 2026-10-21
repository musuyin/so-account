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
}

List<MissingImportAccount> missingImportAccounts(
  ImportTable table,
  ImportMapping mapping,
  List<Account> accounts,
) {
  return importAccountSources(table, mapping).where((source) {
    final mapped = mapping.accounts[source.name];
    if (mapped != null && accounts.any((a) => a.id == mapped)) return false;
    return !accounts.any(
      (a) =>
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
