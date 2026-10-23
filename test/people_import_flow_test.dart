import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/app/providers/providers.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';
import 'package:so_account/features/ledger/presentation/people_debts_page.dart';

void main() {
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'person view links each payment to a deliberately selected loan',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => tester.runAsync(db.close));
      await tester.runAsync(() async {
        final ledger = LedgerRepository(db);
        final account = await ledger.saveAccount(
          name: '钱包',
          kind: '资金账户',
          channel: '现金',
          currency: 'CNY',
          openingBalance: 10000,
        );
        await ledger.saveEntry(
          kind: EntryKind.lend,
          amount: 2000,
          accountId: account,
          date: '2026-10-01',
          counterparty: '小林',
        );
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: PeopleDebtsPage()),
        ),
      );
      await settle(tester);
      await tester.tap(find.text('小林'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('收回借出'));
      await tester.pumpAndSettle();
      expect(find.text('往来人：小林'), findsOneWidget);
      expect(
        find.textContaining('小林 · 2026-10-01 · 剩余 CNY 20.00'),
        findsAtLeastNWidgets(1),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );
}
