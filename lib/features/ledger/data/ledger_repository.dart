import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/money/money.dart';
import '../../../core/time/business_date.dart';
import '../../../data/database/app_database.dart';
import '../domain/entry_kind.dart';

class LedgerRepository {
  LedgerRepository(this.db);
  final AppDatabase db;
  final _uuid = const Uuid();

  Stream<List<Account>> watchAccounts() => db.select(db.accounts).watch();
  Stream<List<Category>> watchCategories() => db.select(db.categories).watch();
  Stream<List<Entry>> watchEntries() =>
      (db.select(db.entries)..orderBy([
            (e) => OrderingTerm.desc(e.date),
            (e) => OrderingTerm.desc(e.createdAt),
          ]))
          .watch();
  Stream<List<Budget>> watchBudgets() => db.select(db.budgets).watch();

  Future<void> saveAccount({
    String? id,
    required String name,
    required String kind,
    required String channel,
    required String currency,
    required int openingBalance,
  }) async {
    if (name.trim().isEmpty || name.trim().length > 80) {
      throw const FormatException('账户名称为 1–80 字');
    }
    fractionDigits(currency);
    if (!accountKinds.contains(kind) || !accountChannels.contains(channel)) {
      throw const FormatException('无效账户类型');
    }
    await db.transaction(() async {
      if (id != null) {
        final old = await (db.select(
          db.accounts,
        )..where((a) => a.id.equals(id))).getSingle();
        final used =
            await (db.select(db.entries)..where(
                  (e) => e.accountId.equals(id) | e.targetAccountId.equals(id),
                ))
                .get();
        if (used.isNotEmpty &&
            (old.currency != currency ||
                old.openingBalance != openingBalance)) {
          throw const FormatException('已有流水的账户不能修改币种或初始余额');
        }
      }
      await db
          .into(db.accounts)
          .insertOnConflictUpdate(
            AccountsCompanion.insert(
              id: id ?? _uuid.v4(),
              name: name.trim(),
              kind: kind,
              channel: channel,
              currency: currency,
              openingBalance: Value(openingBalance),
            ),
          );
    });
  }

  Future<void> deleteAccount(String id) async {
    try {
      await (db.delete(db.accounts)..where((a) => a.id.equals(id))).go();
    } on Exception {
      throw const FormatException('账户仍有流水，请先处理流水');
    }
  }

  Future<void> saveCategory(String name, String kind, {String? id}) async {
    if (name.trim().isEmpty ||
        name.trim().length > 40 ||
        !['income', 'expense'].contains(kind)) {
      throw const FormatException('请输入有效的收支分类');
    }
    try {
      await db.transaction(() async {
        if (id != null) {
          final old = await (db.select(
            db.categories,
          )..where((c) => c.id.equals(id))).getSingle();
          if (old.kind != kind) throw const FormatException('不能改变分类的收支类型');
        }
        await db
            .into(db.categories)
            .insertOnConflictUpdate(
              CategoriesCompanion.insert(
                id: id ?? _uuid.v4(),
                name: name.trim(),
                kind: kind,
              ),
            );
      });
    } on FormatException {
      rethrow;
    } on Exception {
      throw const FormatException('此分类名称已存在');
    }
  }

  Future<void> deleteCategory(String id) async {
    try {
      await (db.delete(db.categories)..where((c) => c.id.equals(id))).go();
    } on Exception {
      throw const FormatException('此分类已有账目，无法删除');
    }
  }

  Future<String> saveEntry({
    String? id,
    required EntryKind kind,
    required int amount,
    required String accountId,
    String? targetAccountId,
    String? categoryId,
    String? debtId,
    required String date,
    String note = '',
  }) => db.transaction(() async {
    if (amount <= 0 || amount > 999999999999) {
      throw const FormatException('金额必须大于零且不超出上限');
    }
    parseDate(date);
    if (note.length > 2000) throw const FormatException('备注不能超过 2000 字');
    final account = await (db.select(
      db.accounts,
    )..where((a) => a.id.equals(accountId))).getSingleOrNull();
    if (account == null) throw const FormatException('请选择账户');
    final old = id == null
        ? null
        : await (db.select(
            db.entries,
          )..where((e) => e.id.equals(id))).getSingle();
    if (old != null) {
      final settlements = await (db.select(
        db.entries,
      )..where((e) => e.debtId.equals(old.id))).get();
      if (settlements.isNotEmpty &&
          (kind.name != old.kind ||
              accountId != old.accountId ||
              amount < settlements.fold<int>(0, (s, e) => s + e.amount) ||
              settlements.any((e) => e.date.compareTo(date) < 0))) {
        throw const FormatException('已有还款，不能改变债务类型、账户或使本金小于已还金额、日期晚于还款');
      }
      final links = await (db.select(
        db.purchaseLinks,
      )..where((l) => l.entryId.equals(old.id))).get();
      if (links.isNotEmpty &&
          (kind != EntryKind.expense ||
              account.currency !=
                  (await (db.select(
                        db.accounts,
                      )..where((a) => a.id.equals(old.accountId))).getSingle())
                      .currency)) {
        throw const FormatException('已关联物品，不能改变支出类型或币种');
      }
    }
    if (kind.needsCategory) {
      final category = categoryId == null
          ? null
          : await (db.select(
              db.categories,
            )..where((c) => c.id.equals(categoryId!))).getSingleOrNull();
      if (category == null || category.kind != kind.name) {
        throw const FormatException('请选择对应的收支分类');
      }
    } else {
      categoryId = null;
    }
    if (kind == EntryKind.transfer) {
      final target = targetAccountId == null
          ? null
          : await (db.select(
              db.accounts,
            )..where((a) => a.id.equals(targetAccountId!))).getSingleOrNull();
      if (target == null ||
          target.id == accountId ||
          target.currency != account.currency) {
        throw const FormatException('转账需选择另一个同币种账户');
      }
    } else {
      targetAccountId = null;
    }
    if (kind.isSettlement) {
      final debt = debtId == null
          ? null
          : await (db.select(
              db.entries,
            )..where((e) => e.id.equals(debtId!))).getSingleOrNull();
      if (debt == null ||
          debt.id == id ||
          debt.kind != (kind == EntryKind.repay ? 'borrow' : 'lend')) {
        throw const FormatException('请选择对应的原始借贷');
      }
      final debtAccount = await (db.select(
        db.accounts,
      )..where((a) => a.id.equals(debt.accountId))).getSingle();
      if (debtAccount.currency != account.currency ||
          date.compareTo(debt.date) < 0) {
        throw const FormatException('还款币种须一致，日期不能早于借贷');
      }
      final paid = await (db.select(
        db.entries,
      )..where((e) => e.debtId.equals(debt.id))).get();
      if (paid
              .where((e) => e.id != id)
              .fold<int>(amount, (sum, e) => sum + e.amount) >
          debt.amount) {
        throw const FormatException('还款不能超过剩余本金');
      }
    } else {
      debtId = null;
    }
    final entryId = id ?? _uuid.v4();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db
        .into(db.entries)
        .insertOnConflictUpdate(
          EntriesCompanion.insert(
            id: entryId,
            kind: kind.name,
            amount: amount,
            accountId: accountId,
            targetAccountId: Value(targetAccountId),
            categoryId: Value(categoryId),
            debtId: Value(debtId),
            date: date,
            note: Value(note.trim()),
            createdAt: old?.createdAt ?? now,
            updatedAt: now,
          ),
        );
    return entryId;
  });

  Future<void> deleteEntry(String id) async {
    try {
      await (db.delete(db.entries)..where((e) => e.id.equals(id))).go();
    } on Exception {
      throw const FormatException('此借贷已有还款，请先删除还款记录');
    }
  }

  Future<void> setBudget(String month, String currency, int amount) async {
    parseDate('$month-01');
    fractionDigits(currency);
    if (amount < 0) throw const FormatException('预算不能为负数');
    await db
        .into(db.budgets)
        .insertOnConflictUpdate(
          BudgetsCompanion.insert(
            month: month,
            currency: currency,
            amount: amount,
          ),
        );
  }

  Stream<Map<String, int>> watchBalances() => db
      .customSelect(
        '''
    SELECT a.id, a.opening_balance + COALESCE(SUM(
      CASE WHEN e.target_account_id = a.id THEN e.amount
      WHEN e.kind IN ('income', 'borrow', 'collect') THEN e.amount
      ELSE -e.amount END), 0) AS balance
    FROM accounts a LEFT JOIN entries e ON e.account_id = a.id OR e.target_account_id = a.id
    GROUP BY a.id
  ''',
        readsFrom: {db.accounts, db.entries},
      )
      .watch()
      .map(
        (rows) => {
          for (final r in rows) r.read<String>('id'): r.read<int>('balance'),
        },
      );

  Stream<List<MonthlyTotal>> watchMonthly(String month) => db
      .customSelect(
        '''
    SELECT a.currency, e.kind, SUM(e.amount) AS total FROM entries e
    JOIN accounts a ON a.id = e.account_id
    WHERE e.date >= ? AND e.date < ? AND e.kind IN ('income', 'expense')
    GROUP BY a.currency, e.kind
  ''',
        variables: [
          Variable('$month-01'),
          Variable(
            dateKey(
              DateTime(
                int.parse(month.substring(0, 4)),
                int.parse(month.substring(5)) + 1,
              ),
            ),
          ),
        ],
        readsFrom: {db.accounts, db.entries},
      )
      .watch()
      .map(
        (rows) => rows
            .map(
              (r) => MonthlyTotal(
                r.read<String>('currency'),
                r.read<String>('kind'),
                r.read<int>('total'),
              ),
            )
            .toList(),
      );
}

class MonthlyTotal {
  const MonthlyTotal(this.currency, this.kind, this.amount);
  final String currency;
  final String kind;
  final int amount;
}
