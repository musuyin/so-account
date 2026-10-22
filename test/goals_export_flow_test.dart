import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/app/providers/providers.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/goals/data/goals_repository.dart';
import 'package:so_account/features/goals/presentation/goals_page.dart';
import 'package:so_account/platform/files/file_delivery.dart';

class _Delivery extends FileDelivery {
  _Delivery(this.saved);
  final bool saved;
  String? name, content;
  @override
  Future<bool> save(String name, Uint8List bytes) async {
    this.name = name;
    content = utf8.decode(bytes);
    return saved;
  }
}

void main() {
  for (final saved in [true, false]) {
    testWidgets(
      'goal export uses system save and handles cancellation, saved=$saved',
      (t) async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(() => t.runAsync(db.close));
        await t.runAsync(
          () => GoalsRepository(db)
              .save(name: '相机', kind: 'wish', currency: 'CNY', target: 10000),
        );
        final delivery = _Delivery(saved);
        await t.pumpWidget(
          ProviderScope(
            overrides: [
              databaseProvider.overrideWithValue(db),
              fileDeliveryProvider.overrideWithValue(delivery),
            ],
            child: const MaterialApp(home: GoalsPage()),
          ),
        );
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await t.pumpAndSettle();
        await t.tap(find.byTooltip('导出目标数据'));
        await t.pumpAndSettle();
        await t.tap(find.text('全部目标汇总 CSV'));
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await t.pumpAndSettle();
        expect(delivery.name, startsWith('so-account-goals-summary-'));
        expect(delivery.content, contains('相机'));
        expect(find.textContaining('操作失败'), findsNothing);
        expect(
          find.textContaining('已保存全部目标数据'),
          saved ? findsOneWidget : findsNothing,
        );
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(milliseconds: 1));
      },
    );
  }
}
