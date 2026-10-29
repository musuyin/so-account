import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/ledger/data/ledger_read_repository.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/domain/account_activity.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';

void main() {
  late AppDatabase db;
  late LedgerRepository ledger;
  late LedgerReadRepository reads;
  late String wallet, other, usd;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    ledger = LedgerRepository(db);
    reads = LedgerReadRepository(db);
    Future<String> account(String name, String currency) => ledger.saveAccount(
      name: name,
      kind: '资金账户',
      channel: '现金',
      currency: currency,
      openingBalance: 10000,
    );
    wallet = await account('合成钱包', 'CNY');
    other = await account('合成银行卡', 'CNY');
    usd = await account('合成外币', 'USD');
    await db.batch(
      (b) => b.insertAll(db.entries, [
        for (var i = 0; i < 225; i++)
          EntriesCompanion.insert(
            id: 'entry-${i.toString().padLeft(3, '0')}',
            kind: i % 3 == 0 ? 'income' : 'expense',
            amount: 100 + i,
            accountId: i % 7 == 0 ? usd : wallet,
            categoryId: Value(i % 3 == 0 ? 'income-0' : 'expense-0'),
            date: i % 9 == 0 ? '2026-09-01' : '2026-10-01',
            note: Value(i % 4 == 0 ? 'literal %_ 配件' : '普通合成样例'),
            createdAt: 1,
            updatedAt: 1,
          ),
      ]),
    );
    final loan = await ledger.saveEntry(
      kind: EntryKind.borrow,
      amount: 5000,
      accountId: wallet,
      date: '2026-10-02',
      counterparty: '合成往来',
    );
    await ledger.saveEntry(
      kind: EntryKind.repay,
      amount: 1200,
      accountId: other,
      date: '2026-10-03',
      debtId: loan,
    );
    await ledger.saveEntry(
      kind: EntryKind.transfer,
      amount: 400,
      accountId: wallet,
      targetAccountId: other,
      date: '2026-10-03',
    );
    final balance = (await ledger.balances())[wallet]!;
    await ledger.adjustBalance(
      accountId: wallet,
      desiredBalance: balance + 23,
      expectedBalance: balance,
      at: DateTime(2026, 10, 4),
    );
    await ledger.archiveAccount(other);
  });
  tearDown(() => db.close());

  test(
    'large linked-item sets retain every relationship across reference batches',
    () async {
      final entry = (await db.select(db.entries).get()).firstWhere(
        (e) =>
            e.accountId == wallet &&
            e.kind == 'expense' &&
            e.date.startsWith('2026-10'),
      );
      await db.batch((b) {
        b.insertAll(db.items, [
          for (var i = 0; i < 1201; i++)
            ItemsCompanion.insert(
              id: 'linked-$i',
              name: '合成物品 $i',
              currency: 'CNY',
              createdAt: 1,
              updatedAt: 1,
            ),
        ]);
        b.insertAll(db.purchaseLinks, [
          for (var i = 0; i < 1201; i++)
            PurchaseLinksCompanion.insert(
              itemId: 'linked-$i',
              entryId: entry.id,
            ),
        ]);
      });
      final view = await reads.home((
        month: '2026-10',
        currency: 'CNY',
        day: null,
        kind: null,
        category: null,
        search: '',
        limit: 500,
      ));
      expect(view.data.links.length, 1201);
      expect(view.data.items.map((i) => i.id).toSet().length, 1201);
    },
  );

  test('month paging leaves daily and range aggregates complete; edits reload a unique prefix', () async {
    const q = (
      month: '2026-10',
      currency: 'CNY',
      day: null,
      kind: null,
      category: null,
      search: '',
      limit: 100,
    );
    final view = await reads.home(q);
    final entries = await db.select(db.entries).get();
    final accounts = await db.select(db.accounts).get();
    final cny = accounts
        .where((a) => a.currency == 'CNY')
        .map((a) => a.id)
        .toSet();
    final expected =
        entries
            .where(
              (e) => cny.contains(e.accountId) && e.date.startsWith(q.month),
            )
            .toList()
          ..sort((a, b) {
            final d = b.date.compareTo(a.date);
            if (d != 0) return d;
            final t = b.createdAt.compareTo(a.createdAt);
            return t != 0 ? t : b.id.compareTo(a.id);
          });
    expect(
      view.data.entries.map((e) => e.id),
      expected.take(100).map((e) => e.id),
    );
    expect(view.count, expected.length);
    expect(
      view.daily['2026-10-01']!['expense'],
      expected
          .where((e) => e.kind == 'expense')
          .fold<int>(0, (s, e) => s + e.amount),
    );
    final literal = await reads.home((
      month: q.month,
      currency: q.currency,
      day: null,
      kind: null,
      category: null,
      search: '%_',
      limit: 100,
    ));
    expect(literal.count, expected.where((e) => e.note.contains('%_')).length);
    expect(
      view.filteredDaily['2026-10-01']!['expense'],
      expected
          .where((e) => e.kind == 'expense')
          .fold<int>(0, (s, e) => s + e.amount),
    );
    expect(
      literal.filteredDaily['2026-10-01']!['expense'],
      expected
          .where((e) => e.kind == 'expense' && e.note.contains('%_'))
          .fold<int>(0, (s, e) => s + e.amount),
    );
    final one = await reads.home((
      month: q.month,
      currency: q.currency,
      day: null,
      kind: 'expense',
      category: 'expense-0',
      search: '',
      limit: 1,
    ));
    expect(one.data.entries.length, 1);
    expect(
      one.filteredDaily['2026-10-01']!['expense'],
      view.filteredDaily['2026-10-01']!['expense'],
    );
    expect(one.filteredDaily['2026-10-01']!.containsKey('income'), isFalse);
    final detail = await reads.watchRange(q, '2026-09-01', '2026-10-04').first;
    expect(
      detail.data.entries.every((e) => ['income', 'expense'].contains(e.kind)),
      isTrue,
    );
    expect(detail.count, greaterThan(view.count - 3));

    await ledger.deleteEntry(view.data.entries.last.id);
    final reloaded = await reads.home(q);
    expect(reloaded.data.entries.length, 100);
    expect(reloaded.count, view.count - 1);
    expect(reloaded.data.entries.map((e) => e.id).toSet().length, 100);
    final expanded = await reads.home((
      month: q.month,
      currency: q.currency,
      day: null,
      kind: null,
      category: null,
      search: '',
      limit: 200,
    ));
    expect(expanded.daily, reloaded.daily);
    expect(expanded.totals, reloaded.totals);
  });

  test('SQL account totals match every account activity including debt, archived history and corrections', () async {
    final entries = await db.select(db.entries).get();
    final adjustments = await db.select(db.balanceAdjustments).get();
    final balances = await ledger.balances();
    for (final account in await db.select(db.accounts).get()) {
      final expected = accountActivities(account, entries, adjustments);
      final view = await reads.account((
        id: account.id,
        month: null,
        kind: '',
        search: '',
        limit: 20,
      ));
      expect(view.count, expected.length);
      expect(
        account.openingBalance + view.transactions + view.corrections,
        balances[account.id],
      );
      expect(view.change, expected.fold<int>(0, (s, r) => s + r.delta));
      expect(view.rows.length, expected.length.clamp(0, 20));
      final monthly = await reads.account((
        id: account.id,
        month: '2026-10',
        kind: 'expense',
        search: '%_',
        limit: 10,
      ));
      final filtered = expected.where(
        (r) =>
            r.date.startsWith('2026-10') &&
            r.kind == 'expense' &&
            r.note.contains('%_'),
      );
      expect(monthly.count, filtered.length);
      expect(monthly.change, filtered.fold<int>(0, (s, r) => s + r.delta));
    }
  });

  test(
    'unrelated goal and preference writes do not reload ledger views',
    () async {
      final events = <HomeLedgerView>[];
      final sub = reads
          .watchHome((
            month: '2026-10',
            currency: 'CNY',
            day: null,
            kind: null,
            category: null,
            search: '',
            limit: 10,
          ))
          .listen(events.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(events, isNotEmpty);
      final before = events.length;
      await db
          .into(db.preferences)
          .insertOnConflictUpdate(
            PreferencesCompanion.insert(key: 'theme', value: 'dark'),
          );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(events.length, before);
      await sub.cancel();
    },
  );
}
