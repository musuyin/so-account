import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/app/providers/providers.dart';
import 'package:so_account/core/time/business_date.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';
import 'package:so_account/features/ledger/presentation/account_detail_page.dart';

void main() {
  testWidgets(
    'account detail reconciles balances and filters its own records on a narrow screen',
    (t) async {
      t.view.physicalSize = const Size(320, 850);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => t.runAsync(db.close));
      final id = await t.runAsync(() async {
        final repo = LedgerRepository(db);
        final id = await repo.saveAccount(
          name: '日常钱包',
          kind: '资金账户',
          channel: '现金',
          currency: 'CNY',
          openingBalance: 10000,
        );
        await repo.saveEntry(
          kind: EntryKind.income,
          amount: 2000,
          accountId: id,
          categoryId: 'income-0',
          date: dateKey(DateTime.now()),
          note: '本月工资',
        );
        await repo.adjustBalance(
          accountId: id,
          desiredBalance: 12500,
          expectedBalance: 12000,
          reason: '核对导入',
        );
        return id;
      });
      await t.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(home: AccountDetailPage(id: id!)),
        ),
      );
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await t.pumpAndSettle();
      expect(find.text('125.00'), findsOneWidget);
      expect(t.takeException(), isNull);
      final search = find.byType(TextField);
      await t.ensureVisible(search);
      await t.enterText(search, '本月工资');
      await t.pumpAndSettle();
      await t.ensureVisible(find.textContaining('筛选结果 1 笔'));
      await t.pumpAndSettle();
      expect(
        find.text('${dateKey(DateTime.now())}\n工资 · 本月工资'),
        findsOneWidget,
      );
      await t.ensureVisible(search);
      await t.enterText(search, '不存在的内容');
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('暂无符合条件的记录'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(milliseconds: 1));
    },
  );
}
