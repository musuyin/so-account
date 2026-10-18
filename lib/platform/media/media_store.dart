import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class MediaStore {
  MediaStore(this.root);
  final Directory root;
  Future<void> collectOrphans(Set<String> referenced) async {
    final directory = Directory(p.join(root.path, 'media'));
    if (!await directory.exists()) return;
    final cutoff = DateTime.now().subtract(const Duration(days: 1));
    await for (final file in directory.list(followLinks: false)) {
      if (file is! File) continue;
      final relative = 'media/${p.basename(file.path)}';
      if (referenced.contains(relative) ||
          !RegExp(r'^media/[a-zA-Z0-9_-]+\.(jpg|png|jpeg)$')
              .hasMatch(relative)) {
        continue;
      }
      if ((await file.stat()).modified.isBefore(cutoff)) {
        try {
          await file.delete();
        } on FileSystemException {
          /* Retry on next launch. */
        }
      }
    }
  }

  static Future<MediaStore> open() async =>
      MediaStore(await getApplicationSupportDirectory());
  File resolve(String relative) {
    if (!RegExp(r'^media/[a-zA-Z0-9_-]+\.(jpg|png|jpeg)$').hasMatch(relative)) {
      throw const FormatException('无效图片路径');
    }
    return File(p.join(root.path, relative));
  }

  Future<String> importPhoto(XFile picked) async {
    if (await picked.length() > 10 * 1024 * 1024) {
      throw const FormatException('图片不能超过 10 MB');
    }
    final ext = p.extension(picked.path).toLowerCase() == '.png'
        ? 'png'
        : 'jpg';
    final relative = 'media/${const Uuid().v4()}.$ext';
    final target = resolve(relative);
    await target.parent.create(recursive: true);
    await picked.saveTo(target.path);
    return relative;
  }

  Future<String?> pick(ImageSource source) async {
    final result = await ImagePicker().pickImage(
      source: source,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 85,
    );
    return result == null ? null : importPhoto(result);
  }

  Future<String?> recover() async {
    if (!Platform.isAndroid) return null;
    final result = await ImagePicker().retrieveLostData();
    if (result.exception != null) {
      throw const FormatException('上次照片选择未完成，请重新选择');
    }
    final picked = result.files?.firstOrNull;
    return picked == null ? null : importPhoto(picked);
  }
}
