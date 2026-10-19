import '../../../data/database/app_database.dart';
import '../../ledger/domain/entry_kind.dart';
import 'import_plan.dart';
import 'import_table.dart';

class MissingImportAccount {
  MissingImportAccount(this.name);
  final String name;
  final Set<String> currencies = {};
  final Set<int> rows = {};
  String? firstDate;
}

List<MissingImportAccount> missingImportAccounts(
  ImportTable table,
  ImportMapping mapping,
  List<Account> accounts,
) {
  final sources = <String, MissingImportAccount>{};
  for (var i = 0; i < table.rows.length; i++) {
    final row = table.rows[i];
    final kindValue = mapping.value(row, ImportField.kind);
    final kind = kindValue.isEmpty
        ? mapping.defaultKind
        : detectedKind(mapping.kinds[kindValue] ?? kindValue);
    for (final field in [
      ImportField.account,
      if (kind == EntryKind.transfer) ImportField.target,
    ]) {
      final name = mapping.value(row, field);
      if (name.isEmpty) continue;
      final source = sources.putIfAbsent(
        name,
        () => MissingImportAccount(name),
      );
      source.rows.add(i + 2);
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
  return sources.values.where((source) {
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
