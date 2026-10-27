import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/backup/data/backup_service.dart';
import 'package:so_account/platform/media/media_store.dart';

import 'support/recovery_fixture.dart';

// Separate debug package and private fixture database. Never opens the app ledger.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final support = await getApplicationSupportDirectory();
  final root = Directory('${support.path}/recovery-fixture');
  await root.create(recursive: true);
  final command = File('${support.path}/recovery-command');
  final stage = await command.exists()
      ? (await command.readAsString()).trim()
      : 'idle';
  final report = File('${support.path}/recovery-report.json');
  final db = AppDatabase(NativeDatabase(File('${root.path}/ledger.sqlite')));
  final media = MediaStore(root);
  final backup = BackupService(db, media);
  final expected = File('${root.path}/expected.json');
  final candidate = File('${root.path}/candidate.zip');
  Future<void> verify() async {
    if (jsonEncode(await recoverySnapshot(db, media)) !=
        await expected.readAsString()) {
      throw StateError('Complete fixture snapshot differs after $stage');
    }
  }

  void publish(String status, [String? error]) => report.writeAsStringSync(
    jsonEncode({
      'stage': stage,
      'status': status,
      'fixture': 'synthetic-v1',
      'schema': db.schemaVersion,
      'os': Platform.operatingSystemVersion,
      'error': error,
    }),
    flush: true,
  );
  try {
    switch (stage) {
      case 'seed':
        // Refuse to overwrite a previously seeded run: host must use a fresh
        // dedicated package or explicitly remove only this synthetic fixture.
        if (await expected.exists()) throw StateError('Fixture already seeded');
        await seedRecoveryFixture(db, media);
        await candidate.writeAsBytes(await backup.export(), flush: true);
        final account = (await db.select(db.accounts).get()).first;
        await (db.update(db.accounts)..where((a) => a.id.equals(account.id)))
            .write(const AccountsCompanion(name: Value('恢复前合成账户')));
        await expected.writeAsString(
          jsonEncode(await recoverySnapshot(db, media)),
          flush: true,
        );
      case 'verify' || 'verify-failure':
        await verify();
      case 'restore-failure':
        var injected = false;
        try {
          await backup.restore(
            await candidate.readAsBytes(),
            beforeCommit: () {
              injected = true;
              throw StateError('injected');
            },
          );
        } on StateError {
          if (!injected) rethrow;
        }
        if (!injected) throw StateError('Failure injection was not reached');
        await verify();
      case 'restore-crash':
        await backup.restore(
          await candidate.readAsBytes(),
          beforeCommit: () {
            publish('ready-to-kill');
            // Keep the transaction open until the host kills the actual process.
            while (true) {
              sleep(const Duration(milliseconds: 100));
            }
          },
        );
      case 'restore-success':
        await backup.restore(await candidate.readAsBytes());
        await expected.writeAsString(
          jsonEncode(await recoverySnapshot(db, media)),
          flush: true,
        );
      case 'idle':
        publish('idle');
      default:
        throw StateError('Unknown recovery command: $stage');
    }
    await db.close();
    if (stage != 'idle') publish('passed');
  } catch (error, stack) {
    publish('failed', '$error\n$stack');
    await db.close();
  }
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Synthetic recovery harness: $stage')),
      ),
    ),
  );
}
