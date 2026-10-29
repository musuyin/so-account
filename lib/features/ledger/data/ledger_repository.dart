import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/category_preferences.dart';
import '../../../core/money/money.dart';
import '../../../core/time/business_date.dart';
import '../../../data/app_snapshot.dart';
import '../../../data/category_settings_store.dart';
import '../../../data/database/app_database.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/domain/item_categories.dart';
import '../../inventory/domain/new_purchase_item.dart';
import '../domain/banks.dart';
import '../domain/entry_kind.dart';

class LedgerRepository {
  LedgerRepository(this.db);
  final AppDatabase db;
  final _uuid = const Uuid();

  Stream<List<Account>> watchAccounts() => db.select(db.accounts).watch();
  Stream<List<Category>> watchCategories() => db
      .customSelect('SELECT 1', readsFrom: {db.categories, db.preferences})
      .watch()
      .asyncMap(
        (_) => db.transaction(
          () async => AppSnapshot(
            [],
            await db.select(db.categories).get(),
            [],
            [],
            [],
            [],
            await db.select(db.preferences).get(),
          ).categories,
        ),
      );
  Stream<List<Entry>> watchEntries() =>
      (db.select(db.entries)..orderBy([
            (e) => OrderingTerm.desc(e.date),
            (e) => OrderingTerm.desc(e.createdAt),
          ]))
          .watch();
  Stream<List<Budget>> watchBudgets() => db.select(db.budgets).watch();

  Future<String> saveAccount({
    String? id,
    required String name,
    required String kind,
    required String channel,
    required String currency,
    required int openingBalance,
    String avatar = '',
    String bank = '',
    String customChannel = '',
    String? unitPrice,
    int? creditLimit,
  }) async {
    if (name.trim().isEmpty || name.trim().length > 80) {
      throw const FormatException('账户名称为 1–80 字');
    }
    fractionDigits(currency);
    if (!['', 'wechat', 'alipay', 'bank', 'huabei'].contains(avatar)) {
      throw const FormatException('无效账户头像');
    }
    final type = normalizeAccountType(kind, channel, customChannel.trim());
    kind = type.kind;
    channel = type.channel;
    if (!bankLabels.containsKey(bank)) {
      throw const FormatException('无效银行类型');
    }
    bank = isBankChannel(channel) ? bank : '';
    customChannel = type.custom;
    unitPrice = kind == '投资理财' ? validateUnitPrice(unitPrice) : null;
    if (creditLimit != null &&
        (kind != '信贷账户' || creditLimit < 0 || creditLimit > 999999999999)) {
      throw const FormatException('额度仅适用于信贷账户，须非负且不超出上限');
    }
    if (openingBalance.abs() > 999999999999) {
      throw const FormatException('初始余额超出上限');
    }
    return db.transaction(() async {
      {
        final duplicate =
            await (db.select(db.accounts)..where(
                  (a) =>
                      a.name.equals(name.trim()) &
                      a.currency.equals(currency) &
                      (kind == '债务'
                          ? a.kind.equals(kind) & a.channel.equals(channel)
                          : a.kind.equals('债务').not()) &
                      (id == null
                          ? const Constant(true)
                          : a.id.equals(id).not()),
                ))
                .get();
        if (duplicate.isNotEmpty) {
          if (duplicate.any((a) => a.isArchived)) {
            throw const FormatException('同名账户已归档，请在设置 → 归档账户中恢复，或使用其他名称');
          }
          throw const FormatException('此币种已有同名账户，请使用已有账户或修改名称');
        }
      }
      if (id != null) {
        final old = await (db.select(
          db.accounts,
        )..where((a) => a.id.equals(id))).getSingle();
        if (old.isArchived) {
          throw const FormatException('账户已归档，请先在设置中恢复');
        }
        final products = await (db.select(
          db.investmentProducts,
        )..where((p) => p.accountId.equals(id))).get();
        if (products.isNotEmpty &&
            (kind != '投资理财' || currency != old.currency)) {
          throw const FormatException('已有理财产品，不能改变账户类型或币种');
        }
        final used =
            await (db.select(db.entries)..where(
                  (e) =>
                      e.accountId.equals(id) |
                      e.targetAccountId.equals(id) |
                      e.debtAccountId.equals(id),
                ))
                .get();
        final corrections = await (db.select(
          db.balanceAdjustments,
        )..where((a) => a.accountId.equals(id))).get();
        if ((used.isNotEmpty || corrections.isNotEmpty) &&
            (old.currency != currency ||
                old.openingBalance != openingBalance ||
                (old.kind == '债务') != (kind == '债务') ||
                (old.kind == '债务' && old.channel != channel))) {
          throw const FormatException('已有流水的账户不能改变币种、期初余额或债务方向');
        }
      }
      final accountId = id ?? _uuid.v4();
      await db
          .into(db.accounts)
          .insertOnConflictUpdate(
            AccountsCompanion.insert(
              id: accountId,
              name: name.trim(),
              kind: kind,
              channel: channel,
              currency: currency,
              openingBalance: Value(openingBalance),
              avatar: Value(avatar),
              bank: Value(bank),
              customChannel: Value(customChannel),
              unitPrice: Value(unitPrice),
              creditLimit: Value(creditLimit),
            ),
          );
      if (id != null) {
        await (db.update(db.entries)..where((e) => e.debtAccountId.equals(id)))
            .write(EntriesCompanion(counterparty: Value(name.trim())));
      }
      return accountId;
    });
  }

  Future<void> archiveAccount(String id) => _setArchived(id, true);

  Future<void> restoreAccount(String id) => _setArchived(id, false);

  Future<void> _setArchived(String id, bool archived) async {
    final changed =
        await (db.update(db.accounts)..where((a) => a.id.equals(id))).write(
          AccountsCompanion(isArchived: Value(archived)),
        );
    if (changed == 0) throw const FormatException('账户已不存在');
  }

  Future<void> deleteAccount(String id) => db.transaction(() async {
    final affectedProducts =
        (await (db.select(
              db.entries,
            )..where((e) => e.accountId.equals(id))).get())
            .map((e) => e.investmentProductId)
            .whereType<String>()
            .toSet();
    // Include settlements of deleted principals even when another funds account
    // received or paid them. One statement keeps self-referencing FKs valid and
    // avoids a variable per historical entry for large imported ledgers.
    await db.customUpdate(
      '''WITH RECURSIVE related(id) AS (
        SELECT id FROM entries
        WHERE account_id = ? OR target_account_id = ? OR debt_account_id = ?
        UNION
        SELECT e.id FROM entries e JOIN related r ON e.debt_id = r.id
      ) DELETE FROM entries WHERE id IN (SELECT id FROM related)''',
      variables: [Variable(id), Variable(id), Variable(id)],
      updates: {db.entries, db.purchaseLinks},
      updateKind: UpdateKind.delete,
    );
    await (db.delete(
      db.balanceAdjustments,
    )..where((a) => a.accountId.equals(id))).go();
    await (db.delete(db.accounts)..where((a) => a.id.equals(id))).go();
    for (final product in affectedProducts) {
      await _validateProductCost(product);
    }
  });

  static void validateAdjustment(BalanceAdjustment adjustment) {
    parseDate(adjustment.date);
    if (adjustment.afterBalance.abs() > 999999999999 ||
        adjustment.delta !=
            adjustment.afterBalance - adjustment.beforeBalance ||
        adjustment.delta == 0 ||
        adjustment.reason.length > 200 ||
        adjustment.createdAt < 0) {
      throw const FormatException('余额调整记录无效');
    }
  }

  Future<void> adjustBalance({
    required String accountId,
    required int desiredBalance,
    required int expectedBalance,
    String? expectedCurrency,
    String reason = '',
    bool createEntry = false,
    DateTime? at,
  }) => db.transaction(() async {
    if (desiredBalance.abs() > 999999999999 || reason.trim().length > 200) {
      throw const FormatException('余额超出上限或说明超过 200 字');
    }
    final account = await (db.select(
      db.accounts,
    )..where((a) => a.id.equals(accountId))).getSingleOrNull();
    if (account == null) throw const FormatException('账户已不存在');
    if (account.isArchived) throw const FormatException('账户已归档，请先在设置中恢复');
    if (expectedCurrency != null && account.currency != expectedCurrency) {
      throw const FormatException('账户币种已变化，请重新打开余额调整');
    }
    final current = (await balances())[accountId];
    if (current == null) throw const FormatException('账户已不存在');
    if (current != expectedBalance) {
      throw const FormatException('账户余额已变化，请重新打开余额调整后核对');
    }
    if (current == desiredBalance) return;
    final now = at ?? DateTime.now();
    if (createEntry) {
      if (account.kind == '债务') {
        throw const FormatException('债务账户仅支持直接对齐；收支请记入资金账户');
      }
      final delta = desiredBalance - current;
      final kind = delta > 0 ? EntryKind.income : EntryKind.expense;
      var category =
          await (db.select(
                db.categories,
              )..where((c) => c.kind.equals(kind.name) & c.name.equals('余额调整')))
              .getSingleOrNull();
      if (category == null) {
        await saveCategory('余额调整', kind.name);
        category =
            await (db.select(db.categories)..where(
                  (c) => c.kind.equals(kind.name) & c.name.equals('余额调整'),
                ))
                .getSingle();
      }
      await saveEntry(
        kind: kind,
        amount: delta.abs(),
        accountId: accountId,
        categoryId: category.id,
        date: dateKey(now),
        note: reason.trim().isEmpty ? '余额对齐' : reason.trim(),
      );
      return;
    }
    final adjustment = BalanceAdjustment(
      id: _uuid.v4(),
      accountId: accountId,
      beforeBalance: current,
      afterBalance: desiredBalance,
      delta: desiredBalance - current,
      reason: reason.trim(),
      date: dateKey(now),
      createdAt: now.toUtc().millisecondsSinceEpoch,
    );
    validateAdjustment(adjustment);
    await db.into(db.balanceAdjustments).insert(adjustment);
  });

  Future<void> saveCategory(
    String name,
    String kind, {
    String? id,
    String? iconId,
  }) async {
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
        final categoryId = id ?? _uuid.v4();
        final settings = CategorySettingsStore(db);
        final savedOrder = decodeCategoryOrder(
          await settings.read('category_order_$kind'),
        );
        await db
            .into(db.categories)
            .insertOnConflictUpdate(
              CategoriesCompanion.insert(
                id: categoryId,
                name: name.trim(),
                kind: kind,
              ),
            );
        await settings.ledgerOrder(kind, savedOrder);
        if (iconId != null) {
          await settings.icon(categoryIconsKey, categoryId, iconId);
        }
      });
    } on FormatException {
      rethrow;
    } on Exception {
      throw const FormatException('此分类名称已存在');
    }
  }

  Future<void> reorderCategories(String kind, List<String> ids) =>
      db.transaction(() => CategorySettingsStore(db).ledgerOrder(kind, ids));

  Future<void> deleteCategory(String id) async {
    try {
      await db.transaction(() async {
        final settings = CategorySettingsStore(db);
        await (db.delete(db.categories)..where((c) => c.id.equals(id))).go();
        for (final kind in ['expense', 'income']) {
          await settings.ledgerOrder(
            kind,
            decodeCategoryOrder(await settings.read('category_order_$kind')),
          );
        }
        await settings.removeIcon(categoryIconsKey, id);
      });
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
    String counterparty = '',
    String? debtAccountId,
    String? investmentProductId,
    String? unitPrice,
    required String date,
    String note = '',
    NewPurchaseItem? newItem,
  }) => db.transaction(() async {
    if (!kind.isInvestment &&
        (investmentProductId != null || unitPrice != null)) {
      throw const FormatException('仅投资流水可关联理财产品或单价');
    }
    if (newItem != null) {
      if (kind != EntryKind.expense) {
        throw const FormatException('只有支出可以同步记物');
      }
      if (newItem.category.trim().isEmpty) {
        throw const FormatException('请选择物品类型');
      }
    }
    if (amount <= 0 || amount > 999999999999) {
      throw const FormatException('金额必须大于零且不超出上限');
    }
    parseDate(date);
    counterparty = counterparty.trim();
    if (counterparty.length > 80) throw const FormatException('往来人名称不能超过 80 字');
    if (note.length > 2000) throw const FormatException('备注不能超过 2000 字');
    final account = await (db.select(
      db.accounts,
    )..where((a) => a.id.equals(accountId))).getSingleOrNull();
    if (account == null) throw const FormatException('请选择账户');
    if (account.isArchived) throw const FormatException('账户已归档，请先在设置中恢复');
    if (kind != EntryKind.transfer && account.kind == '债务') {
      throw const FormatException('请选择实际收付款的资金账户，债务账户需单独关联');
    }
    if (kind.isPrincipal) {
      final side = kind == EntryKind.borrow
          ? '应付款'
          : kind == EntryKind.reimburse
          ? '报销'
          : '应收款';
      final person = counterparty.isEmpty ? '未注明往来人' : counterparty;
      Account? debtAccount;
      if (debtAccountId != null) {
        debtAccount = await (db.select(
          db.accounts,
        )..where((a) => a.id.equals(debtAccountId!))).getSingleOrNull();
      } else {
        debtAccount =
            await (db.select(db.accounts)..where(
                  (a) =>
                      a.name.equals(person) &
                      a.currency.equals(account.currency) &
                      a.kind.equals('债务') &
                      a.channel.equals(side),
                ))
                .getSingleOrNull();
        if (debtAccount == null) {
          final id = await saveAccount(
            name: person,
            kind: '债务',
            channel: side,
            currency: account.currency,
            openingBalance: 0,
          );
          debtAccount = await (db.select(
            db.accounts,
          )..where((a) => a.id.equals(id))).getSingle();
        }
      }
      if (debtAccount?.isArchived == true) {
        throw const FormatException('债务账户已归档，请先在设置中恢复');
      }
      if (debtAccount == null ||
          debtAccount.kind != '债务' ||
          debtAccount.currency != account.currency ||
          (debtAccount.channel != side &&
              !(side == '应收款' && debtAccount.channel == '报销'))) {
        throw FormatException('请选择对应币种的$side账户');
      }
      debtAccountId = debtAccount.id;
      counterparty = debtAccount.name;
    }
    final old = id == null
        ? null
        : await (db.select(
            db.entries,
          )..where((e) => e.id.equals(id))).getSingle();
    if (old != null) {
      await _checkEntryAccountsActive(old);
      final settlements = await (db.select(
        db.entries,
      )..where((e) => e.debtId.equals(old.id))).get();
      if (settlements.isNotEmpty &&
          (kind.name != old.kind ||
              debtAccountId != old.debtAccountId ||
              accountId != old.accountId ||
              amount < settlements.fold<int>(0, (s, e) => s + e.amount) ||
              settlements.any((e) => e.date.compareTo(date) < 0))) {
        throw const FormatException('已有还款，不能改变往来人、债务类型、账户或使本金小于已还金额、日期晚于还款');
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
    if (kind == EntryKind.transfer || kind.isInvestment) {
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
      if (target.isArchived) throw const FormatException('转入账户已归档，请先在设置中恢复');
      if (kind.isInvestment) {
        final product = investmentProductId == null
            ? null
            : await (db.select(db.investmentProducts)
                    ..where((p) => p.id.equals(investmentProductId!)))
                  .getSingleOrNull();
        if (account.kind == '债务' ||
            target.kind != '投资理财' ||
            product == null ||
            product.accountId != target.id) {
          throw const FormatException('请选择同币种理财账户及其产品');
        }
        unitPrice = validateUnitPrice(unitPrice);
      }
      for (final side in [account, target].where((a) => a.kind == '债务')) {
        final loans = await (db.select(
          db.entries,
        )..where((e) => e.debtAccountId.equals(side.id))).get();
        if (loans.isNotEmpty) {
          throw const FormatException('该债务账户已有分笔借贷，请通过偿还借入或收回借出关联结算');
        }
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
          debt.kind !=
              (kind == EntryKind.repay
                  ? 'borrow'
                  : kind == EntryKind.reimbursement
                  ? 'reimburse'
                  : 'lend')) {
        throw const FormatException('请选择对应的原始借贷');
      }
      await _checkEntryAccountsActive(debt);
      if (debtAccountId != null && debtAccountId != debt.debtAccountId) {
        throw const FormatException('回款或还款账户须与原始记录关联的对象一致');
      }
      if (counterparty.isNotEmpty && counterparty != debt.counterparty) {
        throw const FormatException('还款往来人须与原始借贷一致');
      }
      counterparty = debt.counterparty;
      debtAccountId = debt.debtAccountId;
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
      if (!kind.isPrincipal) {
        counterparty = '';
        debtAccountId = null;
      }
    }
    if (!kind.isInvestment) {
      investmentProductId = null;
      unitPrice = null;
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
            counterparty: Value(counterparty),
            debtAccountId: Value(debtAccountId),
            investmentProductId: Value(investmentProductId),
            unitPrice: Value(unitPrice),
            date: date,
            note: Value(note.trim()),
            createdAt: old?.createdAt ?? now,
            updatedAt: now,
          ),
        );
    if (old?.investmentProductId != null) {
      await _validateProductCost(old!.investmentProductId!);
    }
    if (investmentProductId != null) {
      await _validateProductCost(investmentProductId!);
    }
    if (newItem != null) {
      await InventoryRepository(db).save(
        name: newItem.name,
        category: encodeItemTags([newItem.category.trim()]),
        currency: account.currency,
        price: newItem.price,
        purchasedOn: date,
        useType: newItem.useType,
        quantity: newItem.quantity,
        unit: newItem.unit,
        entryIds: [entryId],
      );
    }
    return entryId;
  });

  Future<void> _checkEntryAccountsActive(Entry entry) async {
    final archived =
        await (db.select(db.accounts)..where(
              (a) =>
                  a.isArchived.equals(true) &
                  a.id.isIn([
                    entry.accountId,
                    if (entry.targetAccountId != null) entry.targetAccountId!,
                    if (entry.debtAccountId != null) entry.debtAccountId!,
                  ]),
            ))
            .get();
    if (archived.isNotEmpty) throw const FormatException('关联账户已归档，请先在设置中恢复');
  }

  Future<void> deleteEntry(String id) => db.transaction(() async {
    final entry = await (db.select(
      db.entries,
    )..where((e) => e.id.equals(id))).getSingleOrNull();
    if (entry != null) await _checkEntryAccountsActive(entry);
    try {
      await (db.delete(db.entries)..where((e) => e.id.equals(id))).go();
      if (entry?.investmentProductId != null) {
        await _validateProductCost(entry!.investmentProductId!);
      }
    } on FormatException {
      rethrow;
    } on Exception {
      throw const FormatException('此借贷已有还款，请先删除还款记录');
    }
  });

  Future<String> saveInvestmentProduct({
    String? id,
    required String accountId,
    required String name,
    required String kind,
  }) => db.transaction(() async {
    final account = await (db.select(
      db.accounts,
    )..where((a) => a.id.equals(accountId))).getSingleOrNull();
    if (account == null || account.kind != '投资理财' || account.isArchived) {
      throw const FormatException('请选择可用的理财账户');
    }
    if (name.trim().isEmpty ||
        name.trim().length > 80 ||
        !accountTypes['投资理财']!.contains(kind)) {
      throw const FormatException('请输入 1–80 字产品名称及有效类别');
    }
    final duplicate =
        await (db.select(db.investmentProducts)..where(
              (p) =>
                  p.accountId.equals(accountId) &
                  p.name.equals(name.trim()) &
                  (id == null ? const Constant(true) : p.id.equals(id).not()),
            ))
            .get();
    if (duplicate.isNotEmpty) throw const FormatException('此账户已有同名产品');
    if (id != null) {
      final old = await (db.select(
        db.investmentProducts,
      )..where((p) => p.id.equals(id))).getSingle();
      if (old.accountId != accountId) {
        throw const FormatException('产品不能移动到其他账户');
      }
    }
    final productId = id ?? _uuid.v4();
    await db
        .into(db.investmentProducts)
        .insertOnConflictUpdate(
          InvestmentProductsCompanion.insert(
            id: productId,
            accountId: accountId,
            name: name.trim(),
            kind: kind,
          ),
        );
    return productId;
  });

  Future<void> deleteInvestmentProduct(String id) => db.transaction(() async {
    final product = await (db.select(
      db.investmentProducts,
    )..where((p) => p.id.equals(id))).getSingle();
    final account = await (db.select(
      db.accounts,
    )..where((a) => a.id.equals(product.accountId))).getSingle();
    if (account.isArchived) throw const FormatException('账户已归档，请先恢复');
    if ((await (db.select(
      db.entries,
    )..where((e) => e.investmentProductId.equals(id))).get()).isNotEmpty) {
      throw const FormatException('已有流水的产品不能删除');
    }
    await (db.delete(
      db.investmentProducts,
    )..where((p) => p.id.equals(id))).go();
  });

  Future<void> _validateProductCost(String id) async {
    final rows =
        await (db.select(db.entries)
              ..where((e) => e.investmentProductId.equals(id))
              ..orderBy([
                (e) => OrderingTerm.asc(e.date),
                (e) => OrderingTerm.asc(e.createdAt),
                (e) => OrderingTerm.asc(e.id),
              ]))
            .get();
    var cost = 0;
    final daily = <String, int>{};
    for (final e in rows) {
      daily.update(
        e.date,
        (value) => value + (e.kind == 'invest' ? e.amount : -e.amount),
        ifAbsent: () => e.kind == 'invest' ? e.amount : -e.amount,
      );
    }
    for (final change in daily.values) {
      // A date has no intraday transaction time: validate the closing cost.
      cost += change;
      if (cost < 0) {
        throw const FormatException('收回金额不能超过该产品当日可收回的投入成本');
      }
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

  Selectable<QueryRow> _balanceRows() => db.customSelect(
    '''
    SELECT a.id, a.opening_balance + COALESCE((SELECT SUM(b.delta) FROM balance_adjustments b WHERE b.account_id=a.id),0) + COALESCE(SUM(
      CASE WHEN e.debt_account_id = a.id THEN CASE WHEN e.kind IN ('borrow','lend','reimburse') THEN e.amount ELSE -e.amount END
      WHEN e.target_account_id = a.id THEN CASE WHEN e.kind='redeem' THEN -e.amount WHEN a.kind='债务' AND a.channel='应付款' THEN -e.amount ELSE e.amount END
      WHEN a.kind='债务' AND a.channel='应付款' THEN e.amount
      WHEN e.kind IN ('income', 'borrow', 'collect', 'reimbursement', 'redeem') THEN e.amount
      ELSE -e.amount END), 0) AS balance
    FROM accounts a LEFT JOIN entries e ON e.account_id = a.id OR e.target_account_id = a.id OR e.debt_account_id = a.id
    GROUP BY a.id
  ''',
    readsFrom: {db.accounts, db.entries, db.balanceAdjustments},
  );

  Map<String, int> _balanceMap(List<QueryRow> rows) => {
    for (final r in rows) r.read<String>('id'): r.read<int>('balance'),
  };
  Future<Map<String, int>> balances() async =>
      _balanceMap(await _balanceRows().get());
  Stream<Map<String, int>> watchBalances() =>
      _balanceRows().watch().map(_balanceMap);

  Stream<List<MonthlyTotal>> watchMonthly(String month) => db
      .customSelect(
        '''
    SELECT a.currency, e.kind, SUM(e.amount) AS total FROM entries e
    JOIN accounts a ON a.id = e.account_id
    WHERE e.date >= ? AND e.date < ? AND e.kind IN ('income', 'expense', 'borrow', 'lend')
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
