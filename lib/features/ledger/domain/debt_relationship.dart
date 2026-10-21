import '../../../data/database/app_database.dart';

int debtRemaining(Entry debt, Iterable<Entry> entries, {String? excludingId}) =>
    debt.amount -
    entries
        .where((e) => e.debtId == debt.id && e.id != excludingId)
        .fold<int>(0, (sum, e) => sum + e.amount);

class PersonDebtSummary {
  PersonDebtSummary(this.name, this.currency);
  final String name, currency;
  final List<Entry> debts = [];
  int receivable = 0, payable = 0;

  static List<PersonDebtSummary> group(
    List<Entry> entries,
    List<Account> accounts,
  ) {
    final currencies = {for (final a in accounts) a.id: a.currency};
    final groups = <(String, String), PersonDebtSummary>{};
    for (final debt in entries.where(
      (e) => ['borrow', 'lend'].contains(e.kind),
    )) {
      final currency = currencies[debt.accountId];
      if (currency == null) continue;
      final group = groups.putIfAbsent((
        debt.counterparty,
        currency,
      ), () => PersonDebtSummary(debt.counterparty, currency));
      group.debts.add(debt);
      final remaining = debtRemaining(debt, entries);
      if (debt.kind == 'lend') {
        group.receivable += remaining;
      } else {
        group.payable += remaining;
      }
    }
    return groups.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }
}
