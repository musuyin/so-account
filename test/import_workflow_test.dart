import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/importing/domain/import_workflow.dart';
import 'package:so_account/features/importing/domain/import_table.dart';
import 'package:so_account/features/importing/domain/import_plan.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';

void main() {
  test('failed import keeps preview and selection for retry; successful commit cannot repeat', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      final repo = LedgerRepository(db);
      final id = await repo.saveAccount(
        name: '合成重试',
        kind: '资金账户',
        channel: '现金',
        currency: 'CNY',
        openingBalance: 0,
      );
      final flow = ImportWorkflow([
        ImportTable(
          '合成表',
          ['日期', '金额'],
          [
            ['2026-10-27', '7'],
          ],
        ),
      ]);
      final entry = ImportEntry(
        row: 2,
        kind: EntryKind.expense,
        amount: 700,
        accountId: id,
        categoryId: 'expense-0',
        date: '2026-10-27',
        note: '重试保留',
      );
      flow.showPreview([ImportResult(2, entry, null)]);
      await repo.archiveAccount(id);
      await expectLater(flow.commit(db), throwsFormatException);
      expect(flow.stage, ImportStage.preview);
      expect(flow.selected, {2});
      await repo.restoreAccount(id);
      await flow.commit(db);
      expect(flow.stage, ImportStage.completed);
      expect(flow.imported, 1);
      await flow.commit(db);
      expect((await db.select(db.entries).get()).length, 1);
    } finally {
      await db.close();
    }
  });
  test(
    'import cancellation preserves mapping; new file resets stale selection',
    () {
      final table = ImportTable(
        '合成表',
        ['日期', '金额'],
        [
          ['2026-10-27', '7'],
        ],
      );
      final flow = ImportWorkflow([table]);
      expect(flow.stage, ImportStage.columns);
      flow.setupStep = 1;
      flow.showPreview([]);
      expect(flow.stage, ImportStage.preview);
      flow.selected.add(99);
      flow.back();
      expect(flow.stage, ImportStage.accounts);
      expect(flow.mapping.columns[ImportField.date], 0);
      expect(flow.selected, isEmpty);
      flow.load([table]);
      expect(flow.stage, ImportStage.columns);
      expect(flow.imported, isNull);
    },
  );
}
