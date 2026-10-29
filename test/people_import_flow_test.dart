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
      expect(find.text('收回借出'), findsOneWidget);
      expect(find.text('剩余 20.00'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('entry-debt')));
      await tester.pumpAndSettle();
      expect(find.text('剩余 CNY 20.00'), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, '小林').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('5'));
      await tester.tap(find.text('保存'));
      await settle(tester);
      final entries = (await tester.runAsync(
        () => db.select(db.entries).get(),
      ))!;
      expect(
        entries.singleWhere((e) => e.kind == 'collect').debtId,
        entries.singleWhere((e) => e.kind == 'lend').id,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );
}
