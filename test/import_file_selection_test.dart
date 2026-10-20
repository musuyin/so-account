import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/app/providers/providers.dart';
import 'package:so_account/features/importing/presentation/import_page.dart';
import 'package:so_account/platform/files/file_delivery.dart';

class PickedCsv extends FileDelivery {
  @override
  Future<({String name, Uint8List bytes})?> pickImport() async => (
    name: '测试.csv',
    bytes: Uint8List.fromList(utf8.encode('日期,金额\n2026-10-20,12.50')),
  );
}

void main() {
  testWidgets(
    'selecting a real file decodes in a worker without capturing UI state',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            snapshotProvider.overrideWith(
              (ref) => Stream.value(AppSnapshot([], [], [], [], [], [], [])),
            ),
            fileDeliveryProvider.overrideWithValue(PickedCsv()),
          ],
          child: const MaterialApp(home: ImportPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('选择文件'));
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('操作失败'), findsNothing);
      expect(find.text('下一步：账户与分类'), findsOneWidget);
    },
  );
}
