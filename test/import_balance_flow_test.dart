import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/app/providers/providers.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/importing/domain/import_table.dart';
import 'package:so_account/features/importing/presentation/import_page.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';

void main() {
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  for (final adjust in [false, true]) {
    testWidgets(
      'after statement import the user can ${adjust ? 'adjust without transactions' : 'keep current balance'}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(() => tester.runAsync(db.close));
        final repo = LedgerRepository(db);
        final id = await tester.runAsync(
          () => repo.saveAccount(
            name: '钱包',
            kind: '资金账户',
            channel: '现金',
            currency: 'CNY',
            openingBalance: 10000,
          ),
        );
        final table = ImportTable.fromRows('收支', [
          ['日期', '收支类型', '金额', '账户', '类别'],
          ['2026-10-23', '收入', '20', '钱包', '工资'],
          ['2026-10-23', '支出', '10', '钱包', '居住'],
          ['bad', '支出', '0', '不应创建的账户', '不应创建的分类'],
          ['bad', '收入', '5', '', '不应创建的分类'],
          ['bad', '转账', '10', '不应创建的账户', '不应创建的分类'],
        ]);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [databaseProvider.overrideWithValue(db)],
            child: MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ImportPage(initialTables: [table]),
                      ),
                    ),
                    child: const Text('开始导入'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('开始导入'));
        await settle(tester);
        await tester.tap(find.text('下一步：账户与分类'));
        await settle(tester);
        expect(find.text('默认账户'), findsNothing);
        await tester.tap(find.text('预览明细'));
        await settle(tester);
        expect(find.text('忽略 3 条'), findsOneWidget);
        expect(find.text('核对账户余额'), findsNothing);
        await tester.tap(find.text('确认导入 2 条'));
        await settle(tester);
        expect(find.text('核对账户余额'), findsOneWidget);
        expect((await tester.runAsync(repo.balances))![id], 11000);
        if (adjust) {
          await tester.tap(find.text('核对并调整余额'));
          await settle(tester);
          expect(find.text('当前余额 CNY 110.00'), findsOneWidget);
          await tester.tap(find.text('调整余额'));
          await settle(tester);
          final amount = find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == '实际余额',
          );
          await tester.enterText(amount, '90');
          await tester.tap(find.text('保存'));
          await settle(tester);
          expect(find.text('当前余额 CNY 90.00'), findsOneWidget);
          await tester.tap(find.text('完成核对'));
          await settle(tester);
        }
        await tester.tap(find.text('保持当前余额并完成'));
        await settle(tester);
        expect(find.text('开始导入'), findsOneWidget);
        final entries = (await tester.runAsync(
          () => db.select(db.entries).get(),
        ))!;
        expect(entries.length, 2);
        expect(entries.singleWhere((e) => e.kind == 'income').amount, 2000);
        expect(entries.singleWhere((e) => e.kind == 'expense').amount, 1000);
        final accounts = (await tester.runAsync(
          () => db.select(db.accounts).get(),
        ))!;
        expect(accounts.length, 1);
        expect(accounts.single.openingBalance, 10000);
        expect(
          (await tester.runAsync(repo.balances))![id],
          adjust ? 9000 : 11000,
        );
        final changes = (await tester.runAsync(
          () => db.select(db.balanceAdjustments).get(),
        ))!;
        expect(changes.length, adjust ? 1 : 0);
        if (adjust) expect(changes.single.delta, -2000);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
      },
    );
  }
}
