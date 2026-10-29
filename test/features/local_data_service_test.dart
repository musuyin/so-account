import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/data/category_settings_store.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/backup/data/backup_service.dart';
import 'package:so_account/features/backup/domain/backup_codec.dart';
import 'package:so_account/features/inventory/data/inventory_repository.dart';
import 'package:so_account/features/inventory/domain/item_cost.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';
import 'package:so_account/features/ledger/domain/default_categories.dart';
import 'package:so_account/features/settings/data/local_data_service.dart';
import 'package:so_account/platform/media/media_store.dart';

import '../../integration_test/support/recovery_fixture.dart';

void main() {
  late Directory root, support, cache;
  late AppDatabase db;
  late LocalDataService service;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('so_local_data_');
    support = await Directory('${root.path}/support').create();
    cache = await Directory('${root.path}/cache').create();
    db = AppDatabase(NativeDatabase(File('${support.path}/so_account.sqlite')));
    final journal = await db
        .customSelect('PRAGMA journal_mode = WAL')
        .getSingle();
    expect(journal.read<String>('journal_mode'), 'wal');
    service = LocalDataService(
      db,
      paths: () async => LocalDataPaths(support, cache),
    );
    await seedRecoveryFixture(db, MediaStore(support));
    final ledger = LedgerRepository(db);
    final finance = await ledger.saveAccount(
      name: '合成理财账户',
      kind: '投资理财',
      channel: '基金',
      currency: 'CNY',
      openingBalance: 0,
    );
    final product = await ledger.saveInvestmentProduct(
      accountId: finance,
      name: '合成基金',
      kind: '基金',
    );
    final source = (await db.select(db.accounts).get()).firstWhere(
      (a) => a.kind == '资金账户' && a.currency == 'CNY',
    );
    await ledger.saveEntry(
      kind: EntryKind.invest,
      amount: 100,
      accountId: source.id,
      targetAccountId: finance,
      investmentProductId: product,
      date: '2026-10-01',
    );
    await db
        .into(db.preferences)
        .insertOnConflictUpdate(
          PreferencesCompanion.insert(key: 'theme', value: 'dark'),
        );
    await db
        .into(db.preferences)
        .insertOnConflictUpdate(
          PreferencesCompanion.insert(key: 'palette', value: 'lavender'),
        );
    await LedgerRepository(db)
        .saveCategory('合成自定义分类', 'expense', iconId: 'camera');
    await InventoryRepository(db).saveCategory('合成自定义种类', iconId: 'book');
    await File('${support.path}/updates.json')
        .writeAsString('{"automatic":false}');
    await Directory('${cache.path}/app-updates').create();
    await File('${cache.path}/app-updates/update.apk').writeAsBytes([1, 2]);
    await File('${cache.path}/so-account-backup.zip').writeAsBytes([3]);
    await File('${root.path}/external-backup.zip').writeAsBytes([4]);
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  Future<void> expectBusinessEmpty() async {
    for (final table in db.allTables.where(
      (t) => !['categories', 'preferences'].contains(t.actualTableName),
    )) {
      expect(
        await db.select(table).get(),
        isEmpty,
        reason: table.actualTableName,
      );
    }
    expect(await CategorySettingsStore(db).read(localCleanupKey), isNull);
    expect(await File('${root.path}/external-backup.zip').readAsBytes(), [4]);
    expect(await support.exists(), isTrue);
    expect(await File('${support.path}/so_account.sqlite').exists(), isTrue);
    final oldName = String.fromCharCodes(utf8.encode('合成钱包'));
    for (final suffix in ['', '-wal']) {
      final file = File('${support.path}/so_account.sqlite$suffix');
      if (await file.exists()) {
        expect(
          String.fromCharCodes(await file.readAsBytes()),
          isNot(contains(oldName)),
        );
      }
    }
  }

  test('clear data removes every business table, photos and cache, retaining categories, order, icons and settings', () async {
    final categories = await db.select(db.categories).get();
    final prefs = await db.select(db.preferences).get();
    final photos = (await db.select(db.items).get())
        .map((i) => i.photo)
        .whereType<String>()
        .toList();
    await service.execute(LocalDataAction.clearData);
    await expectBusinessEmpty();
    expect(await db.select(db.categories).get(), categories);
    for (final p in prefs.where((p) => p.key != 'account_order')) {
      expect(await CategorySettingsStore(db).read(p.key), p.value);
    }
    for (final photo in photos) {
      expect(await MediaStore(support).resolve(photo).exists(), isFalse);
    }
    expect(
      await File('${support.path}/updates.json').readAsString(),
      '{"automatic":false}',
    );
    expect(
      await File('${cache.path}/app-updates/update.apk').exists(),
      isFalse,
    );
    expect(await File('${cache.path}/so-account-backup.zip').exists(), isFalse);
    await LedgerRepository(db).saveAccount(
      name: '清空后合成账户',
      kind: '资金账户',
      channel: '现金',
      currency: 'CNY',
      openingBalance: 0,
    );
    expect(await db.select(db.accounts).get(), hasLength(1));
  });

  test('reset recreates only latest defaults and settings, surviving close/reopen without old categories returning', () async {
    await service.execute(LocalDataAction.resetApp);
    await expectBusinessEmpty();
    var categories = await db.select(db.categories).get();
    expect(
      categories.map((c) => c.name),
      [...expenseDefaults, ...incomeDefaults].map((c) => c.name),
    );
    expect(await CategorySettingsStore(db).read('theme'), isNull);
    expect(await CategorySettingsStore(db).read('palette'), isNull);
    expect(
      jsonDecode((await CategorySettingsStore(db).read('item_categories'))!),
      itemCategories,
    );
    expect(await File('${support.path}/updates.json').exists(), isFalse);
    await db.close();
    db = AppDatabase(NativeDatabase(File('${support.path}/so_account.sqlite')));
    categories = await db.select(db.categories).get();
    expect(
      categories.map((c) => c.name),
      [...expenseDefaults, ...incomeDefaults].map((c) => c.name),
    );
    expect(categories.map((c) => c.name), isNot(contains('普通餐饮')));
    expect(categories.map((c) => c.name), isNot(contains('合成自定义分类')));
  });

  test('a failure before commit restores all rows and leaves photos/settings untouched', () async {
    final before = await recoverySnapshot(db, MediaStore(support));
    await expectLater(
      service.execute(
        LocalDataAction.resetApp,
        beforeCommit: () => throw StateError('simulated failure'),
      ),
      throwsStateError,
    );
    expect(await recoverySnapshot(db, MediaStore(support)), before);
    expect(await File('${cache.path}/app-updates/update.apk').exists(), isTrue);
    expect(await File('${support.path}/updates.json').exists(), isTrue);
    expect(await CategorySettingsStore(db).read(localCleanupKey), isNull);
  });

  test('file failure retains a durable receipt; reopening resumes only old-file cleanup without clearing new rows', () async {
    final failing = LocalDataService(
      db,
      paths: () async => LocalDataPaths(support, cache),
      deleteFile: (_) async => throw const FileSystemException('locked'),
    );
    await expectLater(
      failing.execute(LocalDataAction.resetApp),
      throwsA(isA<LocalCleanupException>()),
    );
    expect(await db.select(db.accounts).get(), isEmpty);
    expect(await CategorySettingsStore(db).read(localCleanupKey), isNotNull);
    // An internal receipt cannot be exported and restored on another device.
    final files = decodeBackup(
      await BackupService(db, MediaStore(support)).export(),
    );
    final backup = jsonDecode(utf8.decode(files['data.json']!)) as Map;
    expect(
      (backup['preferences'] as List).any((p) => p['key'] == localCleanupKey),
      isFalse,
    );
    await LedgerRepository(db).saveAccount(
      name: '重试不应删除的合成账户',
      kind: '资金账户',
      channel: '现金',
      currency: 'CNY',
      openingBalance: 0,
    );
    await File('${support.path}/media/new-photo.jpg').writeAsBytes([9]);
    await db.close();
    db = AppDatabase(NativeDatabase(File('${support.path}/so_account.sqlite')));
    final retry = LocalDataService(
      db,
      paths: () async => LocalDataPaths(support, cache),
    );
    expect(await retry.resumeCleanup(), LocalDataAction.resetApp);
    expect((await db.select(db.accounts).get()).single.name, '重试不应删除的合成账户');
    expect(await File('${support.path}/media/new-photo.jpg').readAsBytes(), [
      9,
    ]);
    expect(await CategorySettingsStore(db).read(localCleanupKey), isNull);
  });

  test('invalid receipt paths cannot delete an external backup or the open database', () async {
    final settings = CategorySettingsStore(db);
    for (final file in [
      {'source': 'media', 'path': '../../external-backup.zip'},
      {'source': 'support', 'path': 'so_account.sqlite'},
    ]) {
      await settings.write(localCleanupKey, {
        'version': 1,
        'id': 'test',
        'action': 'resetApp',
        'files': [file],
      });
      await expectLater(
        service.resumeCleanup(),
        throwsA(isA<LocalCleanupException>()),
      );
      expect(await File('${root.path}/external-backup.zip').readAsBytes(), [4]);
      expect(await db.select(db.accounts).get(), isNotEmpty);
    }
  });
  test(
    'overlapping support/cache roots fail before deleting any data',
    () async {
      final unsafe = LocalDataService(
        db,
        paths: () async => LocalDataPaths(support, support),
      );
      await expectLater(
        unsafe.execute(LocalDataAction.resetApp),
        throwsFormatException,
      );
      expect(await db.select(db.accounts).get(), isNotEmpty);
      expect(await File('${support.path}/updates.json').exists(), isTrue);
    },
  );

  test(
    'a replaced media root cannot redirect cleanup into exported files',
    () async {
      final oldMedia = Directory('${support.path}/media');
      final savedMedia = await oldMedia.rename('${support.path}/saved-media');
      final external = await Directory('${root.path}/exported').create();
      await File('${external.path}/keep.jpg').writeAsBytes([7]);
      await Link(oldMedia.path).create(external.path);
      try {
        await CategorySettingsStore(db).write(localCleanupKey, {
          'version': 1,
          'id': 'test',
          'action': 'resetApp',
          'files': [
            {'source': 'media', 'path': 'keep.jpg'},
          ],
        });
        await expectLater(
          service.resumeCleanup(),
          throwsA(isA<LocalCleanupException>()),
        );
        expect(await File('${external.path}/keep.jpg').readAsBytes(), [7]);
      } finally {
        await Link(oldMedia.path).delete();
        await savedMedia.rename(oldMedia.path);
      }
    },
    skip: Platform.isWindows
        ? 'Windows symlinks need permissions; run this case on Linux'
        : false,
  );
}
