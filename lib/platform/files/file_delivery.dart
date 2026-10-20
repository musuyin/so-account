import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class FileDelivery {
  FileDelivery({Future<PlatformFile?> Function()? selectImport})
    : _selectImport = selectImport ?? _pickImport;
  final Future<PlatformFile?> Function() _selectImport;

  static Future<PlatformFile?> _pickImport() => FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['csv', 'xlsx', 'xls'],
  );

  Future<({String name, Uint8List bytes})?> pickImport() async {
    try {
      final result = await _selectImport();
      if (result == null) return null;
      if ((result.lengthSync() ?? 0) > 10 * 1024 * 1024) {
        throw const FormatException('导入文件不能超过 10 MB');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in result.readAsByteStream()) {
        if (bytes.length + chunk.length > 10 * 1024 * 1024) {
          throw const FormatException('导入文件不能超过 10 MB');
        }
        bytes.add(chunk);
      }
      if (bytes.isEmpty) throw const FormatException('文件内容为空，请重新选择');
      return (name: result.name, bytes: bytes.takeBytes());
    } on FormatException {
      rethrow;
    } on PlatformException catch (e) {
      throw FormatException('文件选择或读取失败（${e.code}）。请确认文件已下载到本机、可正常打开，再重新选择');
    } on FileSystemException catch (e) {
      throw FormatException(
        '无法读取文件（系统错误 ${e.osError?.errorCode ?? '未知'}）。请将文件保存到本机后重试',
      );
    } catch (e) {
      throw FormatException('文件读取失败（${e.runtimeType}），请重新选择本机文件后重试');
    }
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
