import 'package:drift/drift.dart';

import '../../../data/app_snapshot.dart';
import '../../../data/database/app_database.dart';
import '../domain/account_activity.dart';
import '../domain/entry_kind.dart';

typedef HomeQuery = ({
  String month,
  String currency,
  String? day,
  String? kind,
  String? category,
  String search,
  int limit,
});
typedef AccountQuery = ({
  String id,
  String? month,
  String kind,
  String search,
  int limit,
});

class HomeLedgerView {
  const HomeLedgerView(
    this.data,
    this.daily,
    this.totals,
    this.count,
    this.monthCount,
  );
  final AppSnapshot data;
  final Map<String, Map<String, int>> daily;
  final Map<String, int> totals;
  final int count, monthCount;
}

class AccountLedgerView {
  const AccountLedgerView(
    this.data,
    this.rows,
    this.count,
    this.change,
    this.transactions,
    this.corrections,
  );
  final AppSnapshot data;
  final List<AccountActivity> rows;
  final int count, change, transactions, corrections;
}

/// Coherent scoped reads. LIMIT bounds the visible prefix; every invalidation
/// re-reads that prefix with a unique order, including edits/deletes between loads.
class LedgerReadRepository {
  LedgerReadRepository(this.db);
  final AppDatabase db;

  // Keep reference lookups below SQLite's bound-variable limits even after
  // repeated "show more" or when many items link to the same expense.
  Future<List<T>> _references<T>(
    Iterable<String> values,
    Future<List<T>> Function(List<String>) read,
  ) async {
    final ids = values.toSet().toList();
    final result = <T>[];
    for (var i = 0; i < ids.length; i += 500) {
      result.addAll(await read(ids.sublist(i, (i + 500).clamp(0, ids.length))));
    }
    return result;
  }

  Stream<T> _watch<T>(
    Set<ResultSetImplementation> tables,
    Future<T> Function() read,
  ) => db
      .customSelect('SELECT 1', readsFrom: tables)
      .watch()
      .asyncMap((_) => db.transaction(read));

  Stream<HomeLedgerView> watchHome(HomeQuery query) => _watch({
    db.accounts,
    db.categories,
    db.entries,
    db.budgets,
    db.items,
    db.purchaseLinks,
  }, () => home(query));

  Future<HomeLedgerView> home(HomeQuery q) => db.transaction(() async {
    final start = '${q.month}-01';
    // ISO dates sort lexicographically; the next month is the exclusive end.
    final date = DateTime.parse(start);
    final end = DateTime(
      date.year,
      date.month + 1,
    ).toIso8601String().substring(0, 10);
    const join =
        'FROM entries e JOIN accounts a ON a.id=e.account_id LEFT JOIN categories c ON c.id=e.category_id';
    const monthWhere = 'a.currency=? AND e.date>=? AND e.date<?';
    final base = <Variable>[
      Variable(q.currency),
      Variable(start),
      Variable(end),
    ];
    final dailyRows = await db
        .customSelect(
          'SELECT e.date, e.kind, SUM(e.amount) AS amount, COUNT(*) AS n $join WHERE $monthWhere GROUP BY e.date,e.kind',
          variables: base,
        )
        .get();
    final daily = <String, Map<String, int>>{}, totals = <String, int>{};
    var monthCount = 0;
    for (final row in dailyRows) {
      final kind = row.read<String>('kind'), amount = row.read<int>('amount');
      monthCount += row.read<int>('n');
      totals.update(kind, (v) => v + amount, ifAbsent: () => amount);
      if (kind == 'income' || kind == 'expense') {
        (daily[row.read<String>('date')] ??= {})[kind] = amount;
      }
    }
    var where = monthWhere;
    final variables = [...base];
    for (final filter in [
      (q.day, 'e.date'),
      (q.kind, 'e.kind'),
      (q.category, 'e.category_id'),
    ]) {
      if (filter.$1 != null) {
        where += ' AND ${filter.$2}=?';
        variables.add(Variable(filter.$1!));
      }
    }
    if (q.search.isNotEmpty) {
      where += " AND instr(lower(e.note || ' ' || e.counterparty || ' ' || COALESCE(c.name,'往来') || ' ' || a.name),lower(?))>0";
      variables.add(Variable(q.search.trim()));
    }
    final count =
        (await db
                .customSelect(
                  'SELECT COUNT(*) AS n $join WHERE $where',
                  variables: variables,
                )
                .getSingle())
            .read<int>('n');
    final rows = await db
        .customSelect(
          'SELECT e.* $join WHERE $where ORDER BY e.date DESC,e.created_at DESC,e.id DESC LIMIT ?',
          variables: [...variables, Variable(q.limit)],
        )
        .get();
    final entries = rows.map((r) => db.entries.map(r.data)).toList();
    final links = await _references(
      entries.map((e) => e.id),
      (ids) => (db.select(
        db.purchaseLinks,
      )..where((l) => l.entryId.isIn(ids))).get(),
    );
    final items = await _references(
      links.map((l) => l.itemId),
      (ids) => (db.select(db.items)..where((i) => i.id.isIn(ids))).get(),
    );
    final data = AppSnapshot(
      await db.select(db.accounts).get(),
      await db.select(db.categories).get(),
      entries,
      await (db.select(db.budgets)..where(
            (b) => b.month.equals(q.month) & b.currency.equals(q.currency),
          ))
          .get(),
      items,
      links,
      const [],
    );
    return HomeLedgerView(data, daily, totals, count, monthCount);
  });

  Stream<AccountLedgerView> watchAccount(AccountQuery query) => _watch({
    db.accounts,
    db.categories,
    db.entries,
    db.balanceAdjustments,
  }, () => account(query));

  Future<AccountLedgerView> account(AccountQuery q) => db.transaction(() async {
    final accounts = await db.select(db.accounts).get();
    final categories = await db.select(db.categories).get();
    final account = accounts.where((a) => a.id == q.id).firstOrNull;
    if (account == null) {
      return AccountLedgerView(
        AppSnapshot(
          accounts,
          categories,
          const [],
          const [],
          const [],
          const [],
          const [],
        ),
        const [],
        0,
        0,
        0,
        0,
      );
    }
    final kindLabels = EntryKind.values
        .map((k) => "WHEN '${k.name}' THEN '${k.label}'")
        .join(' ');
    final label = 'CASE e.kind $kindLabels END';
    // Same precedence as accountEntryDelta, including payable target accounts.
    const delta =
        "CASE WHEN e.debt_account_id=a.id THEN CASE WHEN e.kind IN ('borrow','lend') THEN e.amount ELSE -e.amount END WHEN e.target_account_id=a.id THEN CASE WHEN a.kind='债务' AND a.channel='应付款' THEN -e.amount ELSE e.amount END WHEN a.kind='债务' AND a.channel='应付款' THEN e.amount WHEN e.kind IN ('income','borrow','collect') THEN e.amount ELSE -e.amount END";
    final parts = [
      ('e.category_id IS NOT NULL', "COALESCE(c.name,'往来')"),
      ('src.id<>a.id', 'src.name'),
      ('dst.id<>a.id AND dst.id<>src.id', 'dst.name'),
      (
        'debt.id<>a.id AND debt.id<>src.id AND (dst.id IS NULL OR debt.id<>dst.id)',
        'debt.name',
      ),
      ("e.note<>''", 'e.note'),
    ];
    final earlier = <String>[];
    final descriptionParts = <String>[];
    for (final part in parts) {
      final separator = earlier.isEmpty
          ? "''"
          : "CASE WHEN ${earlier.map((c) => '($c)').join(' OR ')} THEN ' · ' ELSE '' END";
      descriptionParts.add(
        "CASE WHEN ${part.$1} THEN $separator || ${part.$2} ELSE '' END",
      );
      earlier.add(part.$1);
    }
    final description = descriptionParts.join(' || ');
    final activity =
        '''
      SELECT e.id,e.date,e.created_at,e.kind,$label AS label,e.note,$delta AS delta,1 AS is_entry,
        $label || ' ' || $description AS search_text
      FROM entries e JOIN accounts a ON a.id=?
      JOIN accounts src ON src.id=e.account_id LEFT JOIN accounts dst ON dst.id=e.target_account_id
      LEFT JOIN accounts debt ON debt.id=e.debt_account_id LEFT JOIN categories c ON c.id=e.category_id
      WHERE e.account_id=a.id OR e.target_account_id=a.id OR e.debt_account_id=a.id
      UNION ALL
      SELECT id,date,created_at,'adjustment','余额调整',reason,delta,0,
        '余额调整 ' || CASE WHEN reason='' THEN '独立调整，不计入收支' ELSE reason END
      FROM balance_adjustments WHERE account_id=?
    ''';
    final base = <Variable>[Variable(q.id), Variable(q.id)];
    final sums = await db
        .customSelect(
          'SELECT COALESCE(SUM(CASE WHEN is_entry=1 THEN delta ELSE 0 END),0) AS transactions,COALESCE(SUM(CASE WHEN is_entry=0 THEN delta ELSE 0 END),0) AS corrections FROM ($activity)',
          variables: base,
        )
        .getSingle();
    var where = '1=1';
    final filters = [...base];
    if (q.month != null) {
      where += ' AND substr(date,1,7)=?';
      filters.add(Variable(q.month!));
    }
    if (q.kind.isNotEmpty) {
      where += ' AND kind=?';
      filters.add(Variable(q.kind));
    }
    if (q.search.isNotEmpty) {
      where += ' AND instr(lower(search_text),lower(?))>0';
      filters.add(Variable(q.search.trim()));
    }
    final summary = await db
        .customSelect(
          'SELECT COUNT(*) AS n,COALESCE(SUM(delta),0) AS change FROM ($activity) WHERE $where',
          variables: filters,
        )
        .getSingle();
    final rows = await db
        .customSelect(
          'SELECT * FROM ($activity) WHERE $where ORDER BY date DESC,created_at DESC,id DESC,is_entry DESC LIMIT ?',
          variables: [...filters, Variable(q.limit)],
        )
        .get();
    final ids = rows
        .where((r) => r.read<int>('is_entry') == 1)
        .map((r) => r.read<String>('id'))
        .toList();
    final entries = await _references(
      ids,
      (batch) => (db.select(db.entries)..where((e) => e.id.isIn(batch))).get(),
    );
    final byId = {for (final e in entries) e.id: e};
    final activities = rows
        .map(
          (r) => AccountActivity(
            id: r.read<String>('id'),
            date: r.read<String>('date'),
            createdAt: r.read<int>('created_at'),
            delta: r.read<int>('delta'),
            kind: r.read<String>('kind'),
            label: r.read<String>('label'),
            note: r.read<String>('note'),
            entry: r.read<int>('is_entry') == 1
                ? byId[r.read<String>('id')]
                : null,
          ),
        )
        .toList();
    return AccountLedgerView(
      AppSnapshot(
        accounts,
        categories,
        entries,
        const [],
        const [],
        const [],
        const [],
      ),
      activities,
      summary.read<int>('n'),
      summary.read<int>('change'),
      sums.read<int>('transactions'),
      sums.read<int>('corrections'),
    );
  });
}
