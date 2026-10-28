import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/local_data_action.dart';
import '../../../data/category_settings_store.dart';
import '../../../data/database/app_database.dart';
export '../../../core/local_data_action.dart';

class LocalDataPaths {
  const LocalDataPaths(this.support, this.cache);
  final Directory support, cache;
  static Future<LocalDataPaths> open() async {
    // Mobile cache roots are app-private. Some desktop implementations return
    // the user's shared temp folder, which must never be purged as app data.
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw const FormatException('本地数据删除暂仅支持 Android 和 iOS');
    }
    return LocalDataPaths(
      await getApplicationSupportDirectory(),
      await getTemporaryDirectory(),
    );
  }

  Map<String, Directory> get roots {
    final a = p.normalize(support.absolute.path),
        b = p.normalize(cache.absolute.path);
    if (p.equals(a, b) || p.isWithin(a, b) || p.isWithin(b, a)) {
      throw const FormatException('本地数据与缓存目录重叠，无法安全清理');
    }
    return {
      'support': Directory(a),
      'media': Directory(p.join(a, 'media')),
      'cache': Directory(b),
    };
  }
}

class LocalCleanupException implements Exception {
  const LocalCleanupException(this.cause);
  final Object cause;
}

/// Database changes and a durable cleanup receipt commit together. Files are
/// removed only after commit, so a failed transaction leaves photos intact.
/// After an interrupted cleanup, retry only the recorded old files, never new
/// business data. This receipt is local state and is excluded from backups.
class LocalDataService {
  LocalDataService(
    this.db, {
    Future<LocalDataPaths> Function()? paths,
    this.deleteFile,
  }) : paths = paths ?? LocalDataPaths.open;
  final AppDatabase db;
  final Future<LocalDataPaths> Function() paths;
  final Future<void> Function(FileSystemEntity)? deleteFile;
  bool _running = false;

  Future<LocalDataAction?> resumeCleanup() async {
    if (_running) throw const FormatException('正在清理本地数据，请稍候');
    _running = true;
    try {
      return await _cleanup();
    } finally {
      _running = false;
    }
  }

  Future<void> execute(
    LocalDataAction action, {
    void Function()? beforeCommit,
  }) async {
    if (_running) throw const FormatException('正在清理本地数据，请稍候');
    _running = true;
    try {
      if (await CategorySettingsStore(db).read(localCleanupKey) != null) {
        throw const FormatException('上次文件清理尚未完成，请先重试清理');
      }
      final roots = (await paths()).roots;
      final files = <Map<String, String>>[];
      for (final source in ['media', 'cache']) {
        final root = roots[source]!;
        final type = await FileSystemEntity.type(root.path, followLinks: false);
        if (type == FileSystemEntityType.link) {
          if (source == 'cache') throw const FormatException('缓存目录不能是符号链接');
          files.add({'source': 'support', 'path': 'media'});
          continue;
        }
        if (type == FileSystemEntityType.notFound) continue;
        await for (final entity in root.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is File || entity is Link) {
            files.add({
              'source': source,
              'path': p.relative(entity.path, from: root.path),
            });
          }
        }
      }
      if (action == LocalDataAction.resetApp) {
        files.add({'source': 'support', 'path': 'updates.json'});
      }
      await db.customStatement('PRAGMA secure_delete = ON');
      await db.transaction(() async {
        final settings = CategorySettingsStore(db);
        if (await settings.read(localCleanupKey) != null) {
          throw const FormatException('上次文件清理尚未完成，请先重试清理');
        }
        final itemCategories = action == LocalDataAction.clearData
            ? await settings.itemCategories()
            : null;
        await db.delete(db.goalContributions).go();
        await db.delete(db.wishGoals).go();
        await db.delete(db.purchaseLinks).go();
        await db.delete(db.items).go();
        await db.delete(db.entries).go();
        await db.delete(db.balanceAdjustments).go();
        await db.delete(db.accounts).go();
        await db.delete(db.budgets).go();
        if (action == LocalDataAction.resetApp) {
          await db.delete(db.categories).go();
          await db.delete(db.preferences).go();
          await db.seedDefaults();
        } else {
          await settings.write('item_categories', itemCategories!);
          await (db.delete(
            db.preferences,
          )..where((row) => row.key.equals('account_order'))).go();
        }
        await settings.write(localCleanupKey, {
          'version': 1,
          'id': const Uuid().v4(),
          'action': action.name,
          'files': files,
        });
        beforeCommit?.call();
      });
      await _cleanup();
    } finally {
      _running = false;
    }
  }

  Future<LocalDataAction?> _cleanup() async {
    final value = await CategorySettingsStore(db).read(localCleanupKey);
    if (value == null) return null;
    try {
      final receipt = jsonDecode(value) as Map<String, dynamic>;
      if (receipt['version'] != 1 ||
          receipt['id'] is! String ||
          receipt['files'] is! List) {
        throw const FormatException('本地清理记录无效');
      }
      final action = LocalDataAction.values.byName(receipt['action'] as String);
      final roots = (await paths()).roots;
      final targets = <({Directory root, String path})>[];
      final checkedRoots = <String>{};
      for (final entry in receipt['files'] as List) {
        final source = entry['source'] as String,
            relative = entry['path'] as String;
        final root = roots[source];
        if (root == null ||
            relative.isEmpty ||
            p.isAbsolute(relative) ||
            (source == 'support' &&
                !['media', 'updates.json'].contains(relative))) {
          throw const FormatException('本地清理路径无效');
        }
        if (source != 'support' &&
            checkedRoots.add(source) &&
            await FileSystemEntity.type(root.path, followLinks: false) ==
                FileSystemEntityType.link) {
          throw const FormatException('本地清理目录变成了符号链接');
        }
        final path = p.normalize(p.join(root.path, relative));
        if (!p.isWithin(root.path, path)) {
          throw const FormatException('本地清理路径越界');
        }
        targets.add((root: root, path: path));
      }
      for (final target in targets) {
        final type = await FileSystemEntity.type(
          target.path,
          followLinks: false,
        );
        if (type == FileSystemEntityType.notFound) continue;
        // Resolve parents before deleting; never follow a replaced directory
        // symlink into another app or into user-exported backups.
        final actualRoot = await target.root.resolveSymbolicLinks();
        final parent = await Directory(p.dirname(target.path))
            .resolveSymbolicLinks();
        if (!p.equals(actualRoot, parent) && !p.isWithin(actualRoot, parent)) {
          throw const FormatException('本地清理路径包含外部链接');
        }
        if (type == FileSystemEntityType.directory) {
          throw const FormatException('本地清理文件类型发生变化');
        }
        final entity = type == FileSystemEntityType.link
            ? Link(target.path)
            : File(target.path);
        if (deleteFile != null) {
          await deleteFile!(entity);
        } else {
          await entity.delete();
        }
      }
      // Keep the open database connection valid. Compact deleted SQLite pages
      // and truncate its WAL instead of unlinking an in-use database file.
      await db.customStatement('VACUUM');
      final checkpoint = await db
          .customSelect('PRAGMA wal_checkpoint(TRUNCATE)')
          .getSingle();
      if (checkpoint.read<int>('busy') != 0) {
        throw const FileSystemException('数据库清理尚未完成');
      }
      await (db.delete(
        db.preferences,
      )..where((row) => row.key.equals(localCleanupKey))).go();
      return action;
    } catch (error) {
      throw LocalCleanupException(error);
    }
  }
}
