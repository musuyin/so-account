import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

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

class SelectedFiles extends FileDelivery {
  SelectedFiles(this.files);
  final List<({String name, Uint8List bytes})?> files;
  @override
  Future<({String name, Uint8List bytes})?> pickImport() async =>
      files.removeAt(0);
}

void main() {
  Future<void> showImport(WidgetTester tester, FileDelivery delivery) async {
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
  }

  Future<void> select(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.text('选择文件'));
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('picking XLS reaches column mapping with correct sample values', (
    tester,
  ) async {
    await showImport(
      tester,
      SelectedFiles([
        (
          name: '账单.xls',
          bytes: File('test/fixtures/import/ledger.xls').readAsBytesSync(),
        ),
      ]),
    );
    await select(tester);
    expect(find.text('下一步：账户与分类'), findsOneWidget);
    expect(find.textContaining('操作失败'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('invalid file has a persistent explanation and can be retried', (
    tester,
  ) async {
    await showImport(
      tester,
      SelectedFiles([
        (name: '账单.xls', bytes: Uint8List(0)),
        (
          name: '账单.csv',
          bytes: Uint8List.fromList(utf8.encode('日期,金额\n2026-10-20,12.50')),
        ),
      ]),
    );
    await select(tester);
    expect(find.text('文件内容为空，请重新选择'), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
    expect(find.text('文件内容为空，请重新选择'), findsOneWidget);
    await select(tester);
    expect(find.text('文件内容为空，请重新选择'), findsNothing);
    expect(find.text('下一步：账户与分类'), findsOneWidget);
  });
  testWidgets('cancelled file selection leaves the importer ready', (
    tester,
  ) async {
    await showImport(tester, SelectedFiles([null]));
    await select(tester);
    expect(find.text('选择文件'), findsOneWidget);
    expect(find.textContaining('失败'), findsNothing);
    expect(find.text('读取中…'), findsNothing);
  });
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
