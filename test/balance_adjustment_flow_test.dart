import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/app/providers/providers.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/presentation/balance_adjustment_form.dart';

void main() {
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  for (final stale in [false, true]) {
    testWidgets(
      'zero balance adjustment saves without ledger writes; stale=$stale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(() => tester.runAsync(db.close));
        final repo = LedgerRepository(db);
        final account = await tester.runAsync(() async {
          final id = await repo.saveAccount(
            name: '钱包',
            kind: '资金账户',
            channel: '现金',
            currency: 'CNY',
            openingBalance: 1000,
          );
          return (await db.select(db.accounts).get()).singleWhere(
            (a) => a.id == id,
          );
        });
        await tester.pumpWidget(
          ProviderScope(
            overrides: [databaseProvider.overrideWithValue(db)],
            child: MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => BalanceAdjustmentForm(
                          account: account!,
                          balance: 1000,
                        ),
                      ),
                    ),
                    child: const Text('调整'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('调整'));
        await settle(tester);
        final field = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '实际余额',
        );
        await tester.enterText(field, '0');
        if (stale) {
          await tester.runAsync(
            () => repo.adjustBalance(
              accountId: account!.id,
              desiredBalance: 1200,
              expectedBalance: 1000,
            ),
          );
          await settle(tester);
        }
        await tester.tap(find.text('保存'));
        await settle(tester);
        if (stale) {
          expect(find.textContaining('账户余额已变化'), findsOneWidget);
        } else {
          expect(find.text('调整'), findsOneWidget);
        }
        final balances = await tester.runAsync(repo.balances);
        expect(balances![account!.id], stale ? 1200 : 0);
        expect(
          await tester.runAsync(() => db.select(db.entries).get()),
          isEmpty,
        );
        expect(
          (await tester.runAsync(() => db.select(db.balanceAdjustments).get()))!
              .length,
          1,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
      },
    );
  }
}
