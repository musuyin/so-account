import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class FileDelivery {
  Future<({String name, Uint8List bytes})?> pickImport() async {
    final result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx'],
    );
    if (result == null) return null;
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in result.readAsByteStream()) {
      if (bytes.length + chunk.length > 10 * 1024 * 1024) {
        throw const FormatException('导入文件不能超过 10 MB');
      }
      bytes.add(chunk);
    }
    return (name: result.name, bytes: bytes.takeBytes());
  }

  Future<bool> save(String name, Uint8List bytes) async {
    final result = await FilePicker.saveFile(
      dialogTitle: '保存文件',
      fileName: name,
      bytes: bytes,
    );
    return result != null;
  }

  Future<void> share(String name, Uint8List bytes, Rect origin) async {
    final directory = await getTemporaryDirectory();
    final file = File(p.join(directory.path, name));
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], sharePositionOrigin: origin),
    );
  }

  Future<Uint8List?> pickBackup() async {
    final result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (result == null) return null;
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in result.readAsByteStream()) {
      if (bytes.length + chunk.length > 50 * 1024 * 1024) {
        throw const FormatException('备份文件不能超过 50 MB');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }
}
