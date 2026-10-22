import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const deltaAlgorithm = 'soaccount-copy-v1';
const _maximumApk = 250 * 1024 * 1024;

Future<String> hashApkInBackground(String path) => Isolate.run(
  () async => (await sha256.bind(File(path).openRead()).first).toString(),
);

Future<void> applyDeltaInBackground({
  required String basePath,
  required String patchPath,
  required String outputPath,
  required String baseHash,
  required String targetHash,
  required int targetSize,
}) => Isolate.run(
  () => applyDelta(
    base: File(basePath),
    patch: File(patchPath),
    output: File(outputPath),
    baseHash: baseHash,
    targetHash: targetHash,
    targetSize: targetSize,
  ),
);

class _Reader {
  _Reader(Stream<List<int>> stream) : iterator = StreamIterator(stream);
  final StreamIterator<List<int>> iterator;
  List<int> current = const [];
  int offset = 0;
  Future<Uint8List> read(int size) async {
    final result = Uint8List(size);
    var written = 0;
    while (written < size) {
      if (offset == current.length) {
        if (!await iterator.moveNext()) throw const FormatException('差分包不完整');
        current = iterator.current;
        offset = 0;
        if (current.isEmpty) continue;
      }
      final count = (current.length - offset).clamp(0, size - written);
      result.setRange(written, written + count, current, offset);
      offset += count;
      written += count;
    }
    return result;
  }

  Future<int> number(int bytes) async {
    final data = ByteData.sublistView(await read(bytes));
    return bytes == 4
        ? data.getUint32(0, Endian.little)
        : data.getUint64(0, Endian.little);
  }

  Future<void> end() async {
    if (offset < current.length) throw const FormatException('差分包含多余数据');
    while (await iterator.moveNext()) {
      if (iterator.current.isNotEmpty) throw const FormatException('差分包含多余数据');
    }
  }
}

/// Reconstructs the exact signed APK, using bounded buffers on a worker isolate.
Future<void> applyDelta({
  required File base,
  required File patch,
  required File output,
  required String baseHash,
  required String targetHash,
  required int targetSize,
}) async {
  if (targetSize <= 0 || targetSize > _maximumApk) {
    throw const FormatException('更新包大小无效');
  }
  final headerFile = await patch.open();
  late Uint8List header;
  try {
    header = await headerFile.read(88);
  } finally {
    await headerFile.close();
  }
  if (header.length != 88 ||
      ascii.decode(header.sublist(0, 8), allowInvalid: true) != 'SOADLT01') {
    throw const FormatException('差分格式不支持');
  }
  final data = ByteData.sublistView(header);
  final baseSize = data.getUint64(8, Endian.little);
  String hash(int offset) => header
      .sublist(offset, offset + 32)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  if (baseSize <= 0 ||
      baseSize > _maximumApk ||
      data.getUint64(16, Endian.little) != targetSize ||
      hash(24) != baseHash ||
      hash(56) != targetHash ||
      await base.length() != baseSize ||
      (await sha256.bind(base.openRead()).first).toString() != baseHash) {
    throw const FormatException('差分包与已安装版本不匹配');
  }
  final reader = _Reader(patch.openRead(88).transform(gzip.decoder));
  final input = await base.open();
  final sink = await output.open(mode: FileMode.write);
  var written = 0, complete = false;
  try {
    while (true) {
      final opcode = (await reader.read(1))[0];
      if (opcode == 255) {
        await reader.end();
        break;
      }
      int length;
      var sourceOffset = 0;
      if (opcode == 0) {
        sourceOffset = await reader.number(8);
        length = await reader.number(4);
        if (length <= 0 ||
            length > 4 * 1024 * 1024 ||
            sourceOffset < 0 ||
            sourceOffset + length > baseSize) {
          throw const FormatException('差分复制范围无效');
        }
        await input.setPosition(sourceOffset);
      } else if (opcode == 1) {
        length = await reader.number(4);
        if (length <= 0 || length > 1024 * 1024) {
          throw const FormatException('差分数据块过大');
        }
      } else {
        throw const FormatException('差分指令无效');
      }
      if (written + length > targetSize) {
        throw const FormatException('差分结果超出更新包大小');
      }
      var remaining = length;
      while (remaining > 0) {
        final count = remaining.clamp(0, 65536);
        final block = opcode == 0
            ? await input.read(count)
            : await reader.read(count);
        if (block.length != count) throw const FormatException('原安装包已变化');
        await sink.writeFrom(block);
        remaining -= count;
      }
      written += length;
    }
    await sink.flush();
    if (written != targetSize) throw const FormatException('差分结果大小不符');
    complete = true;
  } finally {
    await input.close();
    await sink.close();
    await reader.iterator.cancel();
    if (!complete && await output.exists()) await output.delete();
  }
  if ((await sha256.bind(output.openRead()).first).toString() != targetHash) {
    await output.delete();
    throw const FormatException('差分合成校验失败');
  }
}
