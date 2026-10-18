import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

const maxBackupBytes = 50 * 1024 * 1024;
const maxExpandedBytes = 100 * 1024 * 1024;
const maxBackupFiles = 1002;
bool validBackupPath(String path) =>
    path == 'data.json' ||
    RegExp(r'^media/[a-zA-Z0-9_-]+\.(jpg|png|jpeg)$').hasMatch(path);

Uint8List encodeBackup(Map<String, Uint8List> files) {
  if (files.length > maxBackupFiles - 1 ||
      files.values.fold<int>(0, (s, b) => s + b.length) > maxExpandedBytes) {
    throw const FormatException('备份超过 100 MB 或 1000 张图片上限');
  }
  final archive = Archive();
  final manifest = <String, Object?>{
    'format': 1,
    'schema': 2,
    'app': 'so_account',
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'files': {
      for (final entry in files.entries)
        entry.key: {
          'size': entry.value.length,
          'sha256': sha256.convert(entry.value).toString(),
        },
    },
  };
  for (final entry in files.entries) {
    if (!validBackupPath(entry.key)) throw const FormatException('无效备份路径');
    archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
  }
  archive.addFile(ArchiveFile.string('manifest.json', jsonEncode(manifest)));
  final result = ZipEncoder().encode(archive);
  if (result.length > maxBackupBytes) {
    throw const FormatException('压缩后的备份超过 50 MB');
  }
  return Uint8List.fromList(result);
}

Map<String, Uint8List> decodeBackup(Uint8List bytes) {
  try {
    if (bytes.length > maxBackupBytes) {
      throw const FormatException('备份文件超过 50 MB');
    }
    // The archive collection merges duplicate names. Inspect the directory
    // before decoding so duplicates and symlinks cannot be hidden by that merge.
    final directory = ZipDirectory()..read(InputMemoryStream(bytes));
    if (directory.fileHeaders.length > maxBackupFiles) {
      throw const FormatException('备份文件数量过多');
    }
    final names = <String>{};
    var expanded = 0;
    for (final header in directory.fileHeaders) {
      final file = header.file;
      if (file == null ||
          !names.add(file.filename) ||
          file.filename != header.filename ||
          (header.externalFileAttributes >> 16) & 0xf000 == 0xa000 ||
          (file.filename != 'manifest.json' &&
              !validBackupPath(file.filename))) {
        throw const FormatException('备份包含重复路径、链接或无效文件');
      }
      expanded += file.uncompressedSize;
      if (file.uncompressedSize < 0 ||
          expanded > maxExpandedBytes ||
          file.filename == 'manifest.json' &&
              file.uncompressedSize > 1024 * 1024) {
        throw const FormatException('解压体积超过限制');
      }
    }
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    if (archive.files.length > maxBackupFiles) {
      throw const FormatException('备份文件数量过多');
    }
    final seen = <String>{};
    var total = 0;
    for (final file in archive.files) {
      if (!file.isFile ||
          file.isSymbolicLink ||
          !seen.add(file.name) ||
          (file.name != 'manifest.json' && !validBackupPath(file.name))) {
        throw const FormatException('备份包含无效路径或重复文件');
      }
      total += file.size;
      if (file.size < 0 ||
          total > maxExpandedBytes ||
          file.name == 'manifest.json' && file.size > 1024 * 1024) {
        throw const FormatException('解压体积超过限制');
      }
    }
    final manifestFile = archive.findFile('manifest.json');
    if (manifestFile == null) throw const FormatException('缺少备份清单');
    final manifest =
        jsonDecode(utf8.decode(manifestFile.content)) as Map<String, dynamic>;
    if (manifest['format'] != 1 ||
        ![1, 2].contains(manifest['schema']) ||
        manifest['app'] != 'so_account') {
      throw const FormatException('不支持的备份版本');
    }
    final declared = manifest['files'] as Map<String, dynamic>;
    if (!declared.containsKey('data.json') ||
        declared.length != archive.files.length - 1) {
      throw const FormatException('备份清单不完整');
    }
    final result = <String, Uint8List>{};
    for (final entry in declared.entries) {
      if (!validBackupPath(entry.key)) throw const FormatException('无效文件路径');
      final file = archive.findFile(entry.key);
      final meta = entry.value as Map<String, dynamic>;
      if (file == null || file.size != meta['size']) {
        throw const FormatException('文件长度不匹配');
      }
      final content = file.content;
      if (content.length != file.size ||
          sha256.convert(content).toString() != meta['sha256']) {
        throw const FormatException('备份文件损坏，校验失败');
      }
      result[entry.key] = Uint8List.fromList(content);
    }
    return result;
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('无法读取备份：格式无效或文件损坏');
  }
}
