import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/backup/data/backup_service.dart';
import 'package:so_account/features/backup/domain/backup_codec.dart';
import 'package:so_account/features/inventory/data/inventory_repository.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';
import 'package:so_account/platform/media/media_store.dart';

void main() {
  late AppDatabase db;
  late Directory root;
  late BackupService service;
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    root = await Directory.systemTemp.createTemp('so_backup_');
    service = BackupService(db, MediaStore(root));
    final ledger = LedgerRepository(db);
    await ledger.saveAccount(
      name: '现金',
      kind: accountKinds.first,
      channel: '现金',
      currency: 'CNY',
      openingBalance: 1234,
    );
    final account = (await db.select(db.accounts).get()).single;
    final expense = await ledger.saveEntry(
      kind: EntryKind.expense,
      amount: 123,
      accountId: account.id,
      categoryId: 'expense-0',
      date: '2026-10-01',
    );
    final photo = File('${root.path}/media/photo.jpg');
    await photo.parent.create();
    await photo.writeAsBytes([1, 2, 3, 4]);
    await InventoryRepository(db).save(
      name: '测试物品',
      category: '生活',
      currency: 'CNY',
      price: 100,
      purchasedOn: '2026-10-01',
      photo: 'media/photo.jpg',
      useType: 'consumable',
      quantity: '250',
      unit: 'ml',
      status: 'unused',
      entryIds: [expense],
    );
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });
  test('v1 backups default avatar and lifecycle fields', () async {
    final files = decodeBackup(await service.export());
    final json =
        jsonDecode(utf8.decode(files['data.json']!)) as Map<String, dynamic>;
    json.remove('adjustments');
    for (final row in json['accounts'] as List) {
      (row as Map).remove('avatar');
    }
    for (final row in json['entries'] as List) {
      (row as Map).remove('counterparty');
    }
    for (final row in json['items'] as List) {
      (row as Map).remove('useType');
      row.remove('status');
      row.remove('archivedOn');
      row.remove('quantity');
      row.remove('unit');
    }
    files['data.json'] = Uint8List.fromList(utf8.encode(jsonEncode(json)));
    final archive = ZipDecoder().decodeBytes(encodeBackup(files));
    final manifest = jsonDecode(
      utf8.decode(archive.findFile('manifest.json')!.content),
    ) as Map<String, dynamic>;
    manifest['schema'] = 1;
    final legacy = Archive();
    for (final file in archive.files) {
      legacy.addFile(
        file.name == 'manifest.json'
            ? ArchiveFile.string('manifest.json', jsonEncode(manifest))
            : ArchiveFile.bytes(file.name, file.content),
      );
    }
    await service.restore(Uint8List.fromList(ZipEncoder().encode(legacy)));
    expect((await db.select(db.accounts).get()).single.avatar, '');
    expect((await db.select(db.items).get()).single.useType, 'durable');
    expect((await db.select(db.items).get()).single.status, 'active');
    expect((await db.select(db.entries).get()).single.counterparty, '');
  });
  test('people and original loan links survive backup and restore', () async {
    final ledger = LedgerRepository(db);
    final account = (await db.select(db.accounts).get()).single;
    final loan = await ledger.saveEntry(
      kind: EntryKind.borrow,
      amount: 10000,
      accountId: account.id,
      date: '2026-10-01',
      counterparty: '小林',
    );
    await ledger.saveEntry(
      kind: EntryKind.repay,
      amount: 1000,
      accountId: account.id,
      date: '2026-10-02',
      debtId: loan,
    );
    final bytes = await service.export();
    await service.restore(bytes);
    final entries = await db.select(db.entries).get();
    expect(entries.singleWhere((e) => e.kind == 'borrow').counterparty, '小林');
    expect(entries.singleWhere((e) => e.kind == 'repay').counterparty, '小林');
    expect(entries.singleWhere((e) => e.kind == 'repay').debtId, loan);
  });
  test('appearance preferences survive backup and restore', () async {
    await db
        .into(db.preferences)
        .insertOnConflictUpdate(
          PreferencesCompanion.insert(
            key: 'item_categories',
            value: '["自定义种类"]',
          ),
        );
    await db
        .into(db.preferences)
        .insertOnConflictUpdate(
          PreferencesCompanion.insert(key: 'palette', value: 'cucumber'),
        );
    await db
        .into(db.preferences)
        .insertOnConflictUpdate(
          PreferencesCompanion.insert(key: 'theme', value: 'dark'),
        );
    final bytes = await service.export();
    await db.delete(db.preferences).go();
    await service.restore(bytes);
    final preferences = {
      for (final pref in await db.select(db.preferences).get())
        pref.key: pref.value,
    };
    expect(preferences['palette'], 'cucumber');
    expect(preferences['theme'], 'dark');
    expect(preferences['item_categories'], '["自定义种类"]');
  });
  test(
    'portable backup restores all tables, photos and associations',
    () async {
      final original = (await db.select(db.items).get()).single;
      final bytes = await service.export();
      final data = decodeBackup(bytes);
      expect(data.keys, contains('media/photo.jpg'));
      await db.delete(db.purchaseLinks).go();
      await db.delete(db.items).go();
      await db.delete(db.entries).go();
      await service.restore(bytes);
      final restored = (await db.select(db.items).get()).single;
      expect(restored.id, original.id);
      expect(restored.createdAt, original.createdAt);
      expect(restored.quantity, '250');
      expect(restored.unit, 'ml');
      expect(restored.status, 'unused');
      expect(await MediaStore(root).resolve(restored.photo!).readAsBytes(), [
        1,
        2,
        3,
        4,
      ]);
      expect((await db.select(db.purchaseLinks).get()).length, 1);
      expect((await db.select(db.entries).get()).single.amount, 123);
    },
  );
  test(
    'transaction failure after replacing rows rolls back the live dataset',
    () async {
      final bytes = await service.export();
      final before = (await db.select(db.items).get()).single;
      await expectLater(
        service.restore(
          bytes,
          beforeCommit: () => throw StateError('injected commit failure'),
        ),
        throwsStateError,
      );
      expect(
        (await db.select(db.items).get()).single.toJson(),
        before.toJson(),
      );
      expect((await db.select(db.entries).get()).length, 1);
      expect((await Directory('${root.path}/media').list().toList()).length, 1);
    },
  );
  test(
    'invalid business data and missing media leave current data untouched',
    () async {
      final files = decodeBackup(await service.export());
      final json =
          jsonDecode(utf8.decode(files['data.json']!)) as Map<String, dynamic>;
      (json['entries'] as List).first['amount'] = -5;
      files['data.json'] = Uint8List.fromList(utf8.encode(jsonEncode(json)));
      await expectLater(
        service.restore(encodeBackup(files)),
        throwsFormatException,
      );
      expect((await db.select(db.entries).get()).single.amount, 123);
      final missing = decodeBackup(await service.export())
        ..remove('media/photo.jpg');
      await expectLater(
        service.restore(encodeBackup(missing)),
        throwsFormatException,
      );
      expect((await db.select(db.items).get()).length, 1);
    },
  );
  test(
    'codec rejects damage, traversal, future formats and duplicate paths',
    () async {
      final files = decodeBackup(await service.export());
      final archive = ZipDecoder().decodeBytes(encodeBackup(files));
      final manifest = jsonDecode(
        utf8.decode(archive.findFile('manifest.json')!.content),
      ) as Map<String, dynamic>;
      manifest['format'] = 999;
      final future = Archive()
        ..addFile(ArchiveFile.string('manifest.json', jsonEncode(manifest)))
        ..addFile(ArchiveFile.bytes('data.json', files['data.json']!));
      expect(
        () => decodeBackup(Uint8List.fromList(ZipEncoder().encode(future))),
        throwsFormatException,
      );
      final traversal = Archive()
        ..addFile(ArchiveFile.string('../data.json', '{}'));
      expect(
        () => decodeBackup(Uint8List.fromList(ZipEncoder().encode(traversal))),
        throwsFormatException,
      );
      final corrupt = Archive()
        ..addFile(
          ArchiveFile.string(
            'manifest.json',
            utf8.decode(archive.findFile('manifest.json')!.content),
          ),
        )
        ..addFile(ArchiveFile.string('data.json', 'tampered'))
        ..addFile(ArchiveFile.bytes('media/photo.jpg', [1, 2, 3, 4]));
      expect(
        () => decodeBackup(Uint8List.fromList(ZipEncoder().encode(corrupt))),
        throwsFormatException,
      );
      final duplicate = Archive()
        ..addFile(ArchiveFile.string('data.json', '{}'))
        ..addFile(ArchiveFile.string('dota.json', '{}'));
      final raw = ZipEncoder().encode(duplicate);
      final pattern = utf8.encode('dota.json');
      for (var i = 0; i <= raw.length - pattern.length; i++) {
        if (List.generate(
          pattern.length,
          (j) => raw[i + j] == pattern[j],
        ).every((v) => v)) {
          raw[i + 1] = 97;
        }
      }
      expect(
        () => decodeBackup(Uint8List.fromList(raw)),
        throwsFormatException,
      );
    },
  );
}
