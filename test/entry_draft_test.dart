import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/ledger/domain/entry_draft.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';

void main() {
  test('kind transitions preserve account/date and invalidate original loan only on change', () {
    final draft = EntryDraft(
      kind: EntryKind.repay,
      date: DateTime(2026, 10, 27),
      accountId: 'fund',
      debtId: 'loan',
      debtAccountId: 'debt',
    );
    draft.changeKind(EntryKind.repay);
    expect(draft.debtId, 'loan');
    draft.exchangeParties();
    expect(draft.kind, EntryKind.collect);
    expect(draft.debtId, isNull);
    expect(draft.debtAccountId, isNull);
    draft.prepareAnother();
    expect(draft.accountId, 'fund');
    expect(draft.date, DateTime(2026, 10, 27));
    draft.changeKind(EntryKind.transfer);
    draft.targetId = 'target';
    draft.exchangeParties();
    expect(draft.accountId, 'target');
    expect(draft.targetId, 'fund');
  });
  test(
    'failed draft save retains choices and rejects archived or deleted account',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        final repo = LedgerRepository(db);
        final id = await repo.saveAccount(
          name: '合成账户',
          kind: '资金账户',
          channel: '现金',
          currency: 'CNY',
          openingBalance: 0,
        );
        final draft = EntryDraft(
          kind: EntryKind.expense,
          date: DateTime(2026, 10, 27),
          accountId: id,
          categoryId: 'expense-0',
        );
        await repo.archiveAccount(id);
        await expectLater(
          draft.save(
            repo,
            currency: 'CNY',
            amount: '7',
            note: '保留备注',
            counterparty: '',
          ),
          throwsFormatException,
        );
        expect(draft.accountId, id);
        expect(draft.categoryId, 'expense-0');
        expect(await db.select(db.entries).get(), isEmpty);
      } finally {
        await db.close();
      }
    },
  );
}
