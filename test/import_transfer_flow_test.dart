import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/app/providers/providers.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/importing/domain/import_table.dart';
import 'package:so_account/features/importing/presentation/import_page.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/platform/files/file_delivery.dart';

class SavedTemplate extends FileDelivery {
  Uint8List? bytes;
  @override
  Future<bool> save(String name, Uint8List bytes) async {
    this.bytes = bytes;
    return true;
  }
}

void main() {
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  for (final targetMissing in [true, false]) {
    for (final cancel in [false, true]) {
      testWidgets(
        'transfer ${targetMissing ? 'destination' : 'source'} creation, cancel=$cancel',
        (tester) async {
          tester.view.physicalSize = const Size(320, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final db = AppDatabase(NativeDatabase.memory());
          addTearDown(() => tester.runAsync(db.close));
          final ledger = LedgerRepository(db);
          final source = targetMissing ? '银行卡' : '新源账户';
          final target = targetMissing ? '新目标账户' : '钱包';
          await tester.runAsync(
            () => ledger.saveAccount(
              name: targetMissing ? source : target,
              kind: '资金账户',
              channel: '现金',
              currency: 'CNY',
              openingBalance: targetMissing ? 10000 : 0,
            ),
          );
          final table = ImportTable.fromRows('转账明细', [
            ['日期', '收支类型', '金额', '源账户', '目标账户'],
            ['2026-10-21', '转账', '10', source, target],
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
          final name = find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == '账户名称',
          );
          expect(
            tester.widget<TextField>(name).controller!.text,
            targetMissing ? target : source,
          );
          expect(
            find.textContaining('用途：转账${targetMissing ? '目标' : '源'}账户'),
            findsOneWidget,
          );
          if (cancel) {
            await tester.tap(find.byType(BackButton).first);
            await tester.pumpAndSettle();
            expect(find.text('预览明细'), findsOneWidget);
            expect(
              await tester.runAsync(() => db.select(db.entries).get()),
              isEmpty,
            );
            expect(
              (await tester.runAsync(() => db.select(db.accounts).get()))!
                  .length,
              1,
            );
          } else {
            for (final entry in {
              '渠道': '现金',
              '账户类型': '资金账户',
              '币种': 'CNY',
            }.entries) {
              final dropdown = find.byWidgetPredicate(
                (w) =>
                    w is DropdownButtonFormField<String> &&
                    w.decoration.labelText == entry.key,
              );
              await tester.scrollUntilVisible(
                dropdown,
                200,
                scrollable: find.byType(Scrollable).last,
              );
              await tester.tap(dropdown);
              await tester.pumpAndSettle();
              await tester.tap(find.text(entry.value).last);
              await tester.pumpAndSettle();
            }
            final opening = find.byWidgetPredicate(
              (w) => w is TextField && w.decoration?.labelText == '初始余额',
            );
            await tester.scrollUntilVisible(
              opening,
              200,
              scrollable: find.byType(Scrollable).last,
            );
            expect(tester.widget<TextField>(opening).controller!.text, '');
            await tester.enterText(opening, targetMissing ? '0' : '100');
            await tester.tap(find.text('保存'));
            await settle(tester);
            expect(find.text('确认导入 1 条'), findsOneWidget);
            expect(find.textContaining('$source → $target'), findsOneWidget);
            expect(
              await tester.runAsync(() => db.select(db.entries).get()),
              isEmpty,
            );
            await tester.tap(find.text('确认导入 1 条'));
            await settle(tester);
            expect(find.text('已导入 1 条明细'), findsOneWidget);
            final entries = await tester.runAsync(
              () => db.select(db.entries).get(),
            );
            expect(entries!.single.kind, 'transfer');
            final accounts = (await tester.runAsync(
              () => db.select(db.accounts).get(),
            ))!;
            final balances = (await tester.runAsync(
              () => ledger.watchBalances().first,
            ))!;
            expect(
              balances[accounts.singleWhere((a) => a.name == source).id],
              9000,
            );
            expect(
              balances[accounts.singleWhere((a) => a.name == target).id],
              1000,
            );
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 1));
        },
      );
    }
  }
  testWidgets(
    'transfer without target column is blocked before account creation',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            snapshotProvider.overrideWith(
              (ref) => Stream.value(AppSnapshot([], [], [], [], [], [], [])),
            ),
          ],
          child: MaterialApp(
            home: ImportPage(
              initialTables: [
                ImportTable.fromRows('test', [
                  ['日期', '收支类型', '金额', '源账户'],
                  ['2026-10-21', '转账', '10', '银行卡'],
                ]),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('下一步：账户与分类'));
      await tester.pumpAndSettle();
      expect(find.text('转账需要目标账户列，请先关联“目标账户”'), findsOneWidget);
      expect(find.text('列名关联'), findsAtLeastNWidgets(1));
    },
  );
  testWidgets(
    'separate downloadable templates preserve statement and transfer structures',
    (tester) async {
      final delivery = SavedTemplate();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            snapshotProvider.overrideWith(
              (ref) => Stream.value(AppSnapshot([], [], [], [], [], [], [])),
            ),
            fileDeliveryProvider.overrideWithValue(delivery),
          ],
          child: const MaterialApp(home: ImportPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存收支 CSV 模板'));
      await tester.pumpAndSettle();
      final table = readImportTables('模板.csv', delivery.bytes!).single;
      expect(table.headers.length, 23);
      expect(table.headers.take(6), ['日期', '收支类型', '金额', '类别', '二级分类', '账户']);
      expect(table.rows.map((r) => r[1]), ['支出', '收入']);
      await tester.tap(find.text('保存转账 CSV 模板'));
      await tester.pumpAndSettle();
      final transfers = readImportTables('转账.csv', delivery.bytes!).single;
      expect(transfers.headers, [
        '日期',
        '类型',
        '转出账户',
        '转入账户',
        '金额',
        '手续费',
        '备注',
        '附件1',
        '附件2',
        '附件3',
        '附件4',
        '附件5',
      ]);
      expect(transfers.rows.single[2], isNot(transfers.rows.single[3]));
    },
  );
}
