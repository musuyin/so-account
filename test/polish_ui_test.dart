import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/app/widgets.dart';
import 'package:so_account/app/providers/providers.dart';
import 'package:so_account/features/inventory/presentation/inventory_page.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/platform/media/media_store.dart';

void main() {
  testWidgets(
    'save action remains visible above a long form on a small screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var saves = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: FormFrame(
            title: '长表单',
            children: List.generate(
              30,
              (i) => TextField(decoration: InputDecoration(labelText: '字段 $i')),
            ),
            onSave: () => saves++,
          ),
        ),
      );
      expect(tester.getBottomRight(find.text('保存')).dy, lessThan(640));
      await tester.tap(find.text('保存'));
      expect(saves, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('inventory searches categories and does not hide unused items', (
    tester,
  ) async {
    final data = AppSnapshot(
      [],
      [],
      [],
      [],
      [
        const Item(
          id: 'tea',
          name: '绿茶',
          category: '食物',
          useType: 'consumable',
          status: 'unused',
          currency: 'CNY',
          note: '',
          createdAt: 0,
          updatedAt: 0,
        ),
        const Item(
          id: 'camera',
          name: '相机',
          category: '数码产品',
          useType: 'durable',
          status: 'active',
          currency: 'CNY',
          note: '',
          createdAt: 1,
          updatedAt: 1,
        ),
      ],
      [],
      [],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          snapshotProvider.overrideWith((ref) => Stream.value(data)),
          mediaProvider.overrideWith(
            (ref) async => MediaStore(Directory.systemTemp),
          ),
        ],
        child: const MaterialApp(home: InventoryPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 件物品'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '食物');
    await tester.pumpAndSettle();
    expect(find.text('1 件物品'), findsOneWidget);
    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pumpAndSettle();
    expect(find.text('2 件物品'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
