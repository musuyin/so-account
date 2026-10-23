import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/backup/data/backup_service.dart';
import 'package:so_account/platform/media/media_store.dart';

void main() {
  test(
    'bank choice survives edits and backup; non-bank channels clear it',
    () async {
      final dir = await Directory.systemTemp.createTemp('so_banks_');
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() async {
        await db.close();
        await dir.delete(recursive: true);
      });
      final repo = LedgerRepository(db);
      final id = await repo.saveAccount(
        name: '银行卡',
        kind: '资金账户',
        channel: '银行卡',
        currency: 'CNY',
        openingBalance: 12300,
        bank: 'cmb',
      );
      final service = BackupService(db, MediaStore(dir));
      final bytes = await service.export();
      await db.delete(db.accounts).go();
      await service.restore(bytes);
      final restored = (await db.select(db.accounts).get()).single;
      expect(restored.id, id);
      expect(restored.bank, 'cmb');
      expect(restored.openingBalance, 12300);
      await repo.saveAccount(
        id: id,
        name: restored.name,
        kind: restored.kind,
        channel: '现金',
        currency: 'CNY',
        openingBalance: 12300,
        bank: restored.bank,
      );
      expect((await db.select(db.accounts).get()).single.bank, '');
      await expectLater(
        repo.saveAccount(
          name: '错误',
          kind: '资金账户',
          channel: '银行卡',
          currency: 'CNY',
          openingBalance: 0,
          bank: 'unknown',
        ),
        throwsFormatException,
      );
    },
  );

  test('v7 account data upgrades to v8 with no bank selected', () async {
    final dir = await Directory.systemTemp.createTemp('so_bank_migration_');
    final file = File('${dir.path}/v7.sqlite');
    final old = AppDatabase(NativeDatabase(file));
    await LedgerRepository(old).saveAccount(
      name: '旧账户',
      kind: '信贷账户',
      channel: '信用卡',
      currency: 'CNY',
      openingBalance: -12345,
      avatar: 'bank',
    );
    // v8 differs from v7 only by this column. Recreate the exact v7 shape.
    await old.customStatement('ALTER TABLE accounts DROP COLUMN bank');
    await old.customStatement('PRAGMA user_version = 7');
    await old.close();
    final next = AppDatabase(NativeDatabase(file));
    try {
      final account = (await next.select(next.accounts).get()).single;
      expect(account.name, '旧账户');
      expect(account.openingBalance, -12345);
      expect(account.avatar, 'bank');
      expect(account.bank, '');
      expect(
        (await next.customSelect('PRAGMA user_version').getSingle())
            .data
            .values
            .single,
        8,
      );
      expect(
        await next.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    } finally {
      await next.close();
      await dir.delete(recursive: true);
    }
  });
}
