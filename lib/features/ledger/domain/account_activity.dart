import '../../../data/database/app_database.dart';
import 'entry_kind.dart';

int accountEntryDelta(Account account, Entry entry) {
  if (entry.debtAccountId == account.id) {
    return ['borrow', 'lend'].contains(entry.kind)
        ? entry.amount
        : -entry.amount;
  }
  if (entry.targetAccountId == account.id) {
    return account.kind == '债务' && account.channel == '应付款'
        ? -entry.amount
        : entry.amount;
  }
  if (entry.accountId != account.id) return 0;
  if (account.kind == '债务' && account.channel == '应付款') return entry.amount;
  return ['income', 'borrow', 'collect'].contains(entry.kind)
      ? entry.amount
      : -entry.amount;
}

class AccountActivity {
  const AccountActivity({
    required this.id,
    required this.date,
    required this.createdAt,
    required this.delta,
    required this.kind,
    required this.label,
    required this.note,
    this.entry,
  });
  final String id, date, kind, label, note;
  final int createdAt, delta;
  final Entry? entry;
}

List<AccountActivity> accountActivities(
  Account account,
  Iterable<Entry> entries,
  Iterable<BalanceAdjustment> adjustments,
) {
  final rows = [
    for (final entry in entries)
      if ([
        entry.accountId,
        entry.targetAccountId,
        entry.debtAccountId,
      ].contains(account.id))
        AccountActivity(
          id: entry.id,
          date: entry.date,
          createdAt: entry.createdAt,
          delta: accountEntryDelta(account, entry),
          kind: entry.kind,
          label: EntryKind.values.byName(entry.kind).label,
          note: entry.note,
          entry: entry,
        ),
    for (final adjustment in adjustments.where(
      (r) => r.accountId == account.id,
    ))
      AccountActivity(
        id: adjustment.id,
        date: adjustment.date,
        createdAt: adjustment.createdAt,
        delta: adjustment.delta,
        kind: 'adjustment',
        label: '余额调整',
        note: adjustment.reason,
      ),
  ];
  rows.sort((a, b) {
    final date = b.date.compareTo(a.date);
    return date != 0 ? date : b.createdAt.compareTo(a.createdAt);
  });
  return rows;
}
