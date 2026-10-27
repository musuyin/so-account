import '../../../core/money/calculator.dart';
import '../../../core/time/business_date.dart';
import '../../inventory/domain/new_purchase_item.dart';
import '../data/ledger_repository.dart';
import 'entry_kind.dart';

/// Composer choices survive cancelled dialogs and failed saves.
class EntryDraft {
  EntryDraft({
    required this.kind,
    required this.date,
    this.accountId,
    this.targetId,
    this.categoryId,
    this.debtId,
    this.debtAccountId,
  });

  EntryKind kind;
  DateTime date;
  String? accountId, targetId, categoryId, debtId, debtAccountId;
  NewPurchaseItem? item;

  void changeKind(EntryKind value) {
    if (value == kind) return;
    kind = value;
    debtId = debtAccountId = null;
  }

  void exchangeParties() {
    if (kind == EntryKind.transfer) {
      if (targetId != null) {
        final previous = accountId;
        accountId = targetId;
        targetId = previous;
      }
    } else {
      changeKind(switch (kind) {
        EntryKind.borrow => EntryKind.lend,
        EntryKind.lend => EntryKind.borrow,
        EntryKind.repay => EntryKind.collect,
        _ => EntryKind.repay,
      });
    }
  }

  // Amount and note controllers are cleared by the view only after success.
  void prepareAnother() => item = null;

  Future<String> save(
    LedgerRepository repository, {
    String? id,
    required String currency,
    required String amount,
    required String note,
    required String counterparty,
  }) {
    if ([EntryKind.borrow, EntryKind.lend].contains(kind) &&
        debtAccountId == null) {
      throw const FormatException('请选择或创建债务账户');
    }
    if (accountId == null) throw const FormatException('请选择收支账户');
    return repository.saveEntry(
      id: id,
      kind: kind,
      amount: calculateMinor(amount, currency),
      accountId: accountId!,
      targetAccountId: targetId,
      categoryId: categoryId,
      debtId: debtId,
      counterparty: kind.isSettlement ? '' : counterparty,
      debtAccountId: debtAccountId,
      date: dateKey(date),
      note: note,
      newItem: kind == EntryKind.expense ? item : null,
    );
  }
}
