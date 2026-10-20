import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/platform/files/file_delivery.dart';

final class ImportSource extends PlatformFile {
  ImportSource(this.stream, {this.size});
  final Stream<Uint8List> Function() stream;
  final int? size;
  @override
  String get name => '中文账单.XLS';
  @override
  Uri get uri => Uri.file('/synthetic.xls');
  @override
  Never get xFile => throw UnimplementedError();
  @override
  int? lengthSync() => size;
  @override
  Future<int?> length() async => size;
  @override
  Future<Uint8List> readAsBytes() => throw UnimplementedError();
  @override
  Stream<Uint8List> readAsByteStream() => stream();
}

Matcher reason(String text) => throwsA(
  isA<FormatException>().having((e) => e.message, 'message', contains(text)),
);

void main() {
  test(
    'reads complete source stream without a local filesystem path',
    () async {
      final delivery = FileDelivery(
        selectImport: () async => ImportSource(
          () => Stream.fromIterable([
            Uint8List.fromList([1, 2]),
            Uint8List.fromList([3, 4]),
          ]),
        ),
      );
      final file = (await delivery.pickImport())!;
      expect(file.name, '中文账单.XLS');
      expect(file.bytes, [1, 2, 3, 4]);
    },
  );
  test('cancel is not an error', () async {
    expect(
      await FileDelivery(selectImport: () async => null).pickImport(),
      isNull,
    );
  });
  test(
    'known oversized files are rejected before opening the byte stream',
    () async {
      var opened = false;
      final source = ImportSource(() {
        opened = true;
        return const Stream.empty();
      }, size: 10 * 1024 * 1024 + 1);
      await expectLater(
        FileDelivery(selectImport: () async => source).pickImport(),
        reason('10 MB'),
      );
      expect(opened, isFalse);
    },
  );
  test('unknown length still enforces streaming size limit and rejects empty content', () async {
    final source = ImportSource(
      () => Stream.fromIterable([
        Uint8List(6 * 1024 * 1024),
        Uint8List(5 * 1024 * 1024),
      ]),
    );
    await expectLater(
      FileDelivery(selectImport: () async => source).pickImport(),
      reason('10 MB'),
    );
    await expectLater(
      FileDelivery(
        selectImport: () async => ImportSource(() => const Stream.empty()),
      ).pickImport(),
      reason('为空'),
    );
  });
  test('picker and provider failures report useful error codes', () async {
    await expectLater(
      FileDelivery(
        selectImport: () async =>
            throw PlatformException(code: 'permission_denied'),
      ).pickImport(),
      reason('permission_denied'),
    );
    final source = ImportSource(
      () => Stream.error(
        const FileSystemException('denied', '', OSError('denied', 13)),
      ),
    );
    await expectLater(
      FileDelivery(selectImport: () async => source).pickImport(),
      reason('系统错误 13'),
    );
  });
}
