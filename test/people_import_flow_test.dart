import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/app/providers/providers.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/importing/domain/import_table.dart';
import 'package:so_account/features/importing/domain/import_template.dart';
import 'package:so_account/features/importing/presentation/import_page.dart';
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

  Future<void> choose(WidgetTester tester, String label, String option) async {
    final field = find.byWidgetPredicate(
      (w) =>
          w is DropdownButtonFormField<String> &&
          w.decoration.labelText == label,
    );
    await tester.scrollUntilVisible(
      field,
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  for (final personal in [false, true]) {
    testWidgets('repayment meaning is explicit; personal=$personal', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => tester.runAsync(db.close));
      final ledger = LedgerRepository(db);
      late String source, original;
      await tester.runAsync(() async {
        source = await ledger.saveAccount(
          name: '钱包',
          kind: '资金账户',
          channel: '现金',
          currency: 'CNY',
          openingBalance: 10000,
        );
        if (personal) {
          original = await ledger.saveEntry(
            kind: EntryKind.borrow,
            amount: 2000,
            accountId: source,
            date: '2026-10-01',
            counterparty: '小林',
          );
        } else {
          await ledger.saveAccount(
            name: '花呗',
            kind: '信贷账户',
            channel: '支付宝',
            currency: 'CNY',
            openingBalance: -10000,
          );
        }
      });
      final table = ImportTable.fromRows('转账', [
        transferTemplateHeaders,
        [
          '2026-10-21',
          '还款',
          '钱包',
          personal ? '小林' : '花呗',
          '10',
          personal ? '0' : '1',
          '',
          '',
          '',
          '',
          '',
          '',
        ],
      ]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(home: ImportPage(initialTables: [table])),
        ),
      );
      await settle(tester);
      await tester.tap(find.text('下一步：账户与分类'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('预览明细'));
      await tester.pumpAndSettle();
      expect(find.textContaining('请先确认“还款”的含义'), findsOneWidget);
      expect(find.text('创建“小林”'), findsNothing);
      await choose(tester, '类型内容：还款', personal ? '向他人还款（偿还借入）' : '信贷账户还款（转账）');
      if (personal) {
        await choose(
          tester,
          '第 2 行原始借贷 · 小林',
          '小林 · 2026-10-01 · 剩余 CNY 20.00',
        );
      }
      await tester.tap(find.text('预览明细'));
      await settle(tester);
      expect(find.text('确认导入 1 条'), findsOneWidget);
      expect(
        find.textContaining(personal ? '往来人 小林' : '手续费 CNY 1.00'),
        findsAtLeastNWidgets(1),
      );
      await tester.tap(find.text('确认导入 1 条'));
      await settle(tester);
      expect(find.text('已导入 1 条明细'), findsOneWidget);
      final entries = (await tester.runAsync(
        () => db.select(db.entries).get(),
      ))!;
      final accounts = (await tester.runAsync(
        () => db.select(db.accounts).get(),
      ))!;
      expect(entries.length, 2);
      expect(accounts.length, personal ? 1 : 2);
      if (personal) {
        expect(entries.singleWhere((e) => e.kind == 'repay').debtId, original);
        expect(
          entries.singleWhere((e) => e.kind == 'repay').counterparty,
          '小林',
        );
      }
      final balances = (await tester.runAsync(
        () => ledger.watchBalances().first,
      ))!;
      expect(balances[source], personal ? 11000 : 8900);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
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
