import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/backup/data/backup_service.dart';
import 'package:so_account/features/backup/domain/backup_codec.dart';
import 'package:so_account/features/ledger/data/ledger_read_repository.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/ledger/domain/account_activity.dart';
import 'package:so_account/features/ledger/domain/entry_kind.dart';
import 'package:so_account/features/statistics/data/statistics_repository.dart';
import 'package:so_account/features/statistics/domain/report_range.dart';
import 'package:so_account/platform/media/media_store.dart';

void main() {
  late AppDatabase db;
  late LedgerRepository repo;
  late String cash, claims, investment, product;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = LedgerRepository(db);
    cash = await repo.saveAccount(
      name: '测试资金',
      kind: '资金账户',
      channel: '现金',
      currency: 'CNY',
      openingBalance: 100000,
    );
    claims = await repo.saveAccount(
      name: '测试单位',
      kind: '债务',
      channel: '报销',
      currency: 'CNY',
      openingBalance: 0,
    );
    investment = await repo.saveAccount(
      name: '测试券商',
      kind: '投资理财',
      channel: '股票',
      currency: 'CNY',
      openingBalance: 500,
    );
    product = await repo.saveInvestmentProduct(
      accountId: investment,
      name: '合成产品',
      kind: '股票',
    );
  });
  tearDown(() => db.close());
  test('restore rejects disconnected reimbursement and non-investment product metadata atomically', () async {
    final debt = await repo.saveEntry(
      kind: EntryKind.reimburse,
      amount: 1000,
      accountId: cash,
      debtAccountId: claims,
      date: '2026-10-01',
    );
    await repo.saveEntry(
      kind: EntryKind.reimbursement,
      amount: 200,
      accountId: cash,
      debtId: debt,
      date: '2026-10-02',
    );
    final root = await Directory.systemTemp.createTemp('finance_bad_backup_');
    final target = AppDatabase(NativeDatabase.memory());
    try {
      final files = decodeBackup(
        await BackupService(db, MediaStore(root)).export(),
      );
      final original = utf8.decode(files['data.json']!);
      for (final kind in ['reimbursement', 'reimburse']) {
        final data = jsonDecode(original) as Map<String, dynamic>;
        final row = (data['entries'] as List)
            .cast<Map<String, dynamic>>()
            .singleWhere((e) => e['kind'] == kind);
        if (kind == 'reimbursement') {
          row['debtAccountId'] = null;
        } else {
          row['investmentProductId'] = product;
        }
        files['data.json'] = Uint8List.fromList(utf8.encode(jsonEncode(data)));
        await expectLater(
          BackupService(target, MediaStore(root)).restore(encodeBackup(files)),
          throwsFormatException,
        );
        expect(await target.select(target.accounts).get(), isEmpty);
      }
    } finally {
      await target.close();
      await root.delete(recursive: true);
    }
  });
  test(
    'schema 9 upgrades retain original transaction, bank and archive data',
    () async {
      final root = await Directory.systemTemp.createTemp('finance_v9_');
      final file = File('${root.path}/old.sqlite');
      final old = AppDatabase(NativeDatabase(file));
      final oldRepo = LedgerRepository(old);
      final account = await oldRepo.saveAccount(
        name: '旧合成账户',
        kind: '资金账户',
        channel: '现金',
        currency: 'CNY',
        openingBalance: 5000,
      );
      final entry = await oldRepo.saveEntry(
        kind: EntryKind.expense,
        amount: 230,
        accountId: account,
        categoryId: 'expense-0',
        date: '2026-09-01',
      );
      await oldRepo.archiveAccount(account);
      for (final sql in [
        'ALTER TABLE entries DROP COLUMN investment_product_id',
        'ALTER TABLE entries DROP COLUMN unit_price',
        'DROP TABLE investment_products',
        'ALTER TABLE accounts DROP COLUMN credit_limit',
        'PRAGMA user_version=9',
      ]) {
        await old.customStatement(sql);
      }
      await old.close();
      final upgraded = AppDatabase(NativeDatabase(file));
      try {
        expect(
          (await upgraded.select(upgraded.accounts).get()).single.isArchived,
          true,
        );
        expect(
          (await upgraded.select(upgraded.accounts).get()).single.creditLimit,
          isNull,
        );
        expect(
          (await upgraded.select(upgraded.entries).get()).single.id,
          entry,
        );
        expect((await LedgerRepository(upgraded).balances())[account], 4770);
        expect(
          await upgraded.select(upgraded.investmentProducts).get(),
          isEmpty,
        );
        expect(
          (await upgraded.customSelect('PRAGMA user_version').getSingle())
              .data
              .values
              .single,
          10,
        );
      } finally {
        await upgraded.close();
        await root.delete(recursive: true);
      }
    },
  );
  test(
    'schema 9 backup restores without optional finance fields or products',
    () async {
      final root = await Directory.systemTemp.createTemp('finance_old_backup_');
      final target = AppDatabase(NativeDatabase.memory());
      try {
        final files = decodeBackup(
          await BackupService(db, MediaStore(root)).export(),
        );
        final data = jsonDecode(
          utf8.decode(files['data.json']!),
        ) as Map<String, dynamic>;
        data.remove('investmentProducts');
        for (final a in data['accounts'] as List) {
          (a as Map).remove('creditLimit');
        }
        files['data.json'] = Uint8List.fromList(utf8.encode(jsonEncode(data)));
        final archive = ZipDecoder().decodeBytes(encodeBackup(files));
        final manifest = jsonDecode(
          utf8.decode(archive.findFile('manifest.json')!.content),
        ) as Map<String, dynamic>;
        manifest['schema'] = 9;
        final oldArchive = Archive();
        for (final f in archive.files) {
          oldArchive.addFile(
            ArchiveFile.bytes(
              f.name,
              f.name == 'manifest.json'
                  ? utf8.encode(jsonEncode(manifest))
                  : f.content,
            ),
          );
        }
        await BackupService(
          target,
          MediaStore(root),
        ).restore(Uint8List.fromList(ZipEncoder().encode(oldArchive)));
        expect(
          await LedgerRepository(target).balances(),
          await repo.balances(),
        );
        expect(await target.select(target.investmentProducts).get(), isEmpty);
        expect(
          (await target.select(target.accounts).get()).every(
            (a) => a.creditLimit == null,
          ),
          isTrue,
        );
      } finally {
        await target.close();
        await root.delete(recursive: true);
      }
    },
  );
  test('archive prevents new reimbursement receipts, investments and product changes', () async {
    final debt = await repo.saveEntry(
      kind: EntryKind.reimburse,
      amount: 1000,
      accountId: cash,
      debtAccountId: claims,
      date: '2026-10-01',
    );
    await repo.archiveAccount(claims);
    await expectLater(
      repo.saveEntry(
        kind: EntryKind.reimbursement,
        amount: 100,
        accountId: cash,
        debtId: debt,
        date: '2026-10-02',
      ),
      throwsFormatException,
    );
    await repo.archiveAccount(investment);
    await expectLater(
      repo.saveInvestmentProduct(
        accountId: investment,
        name: '不能添加',
        kind: '股票',
      ),
      throwsFormatException,
    );
    await expectLater(
      repo.saveEntry(
        kind: EntryKind.invest,
        amount: 100,
        accountId: cash,
        targetAccountId: investment,
        investmentProductId: product,
        date: '2026-10-02',
      ),
      throwsFormatException,
    );
  });
  Future<String> claim({
    int amount = 1500,
    String? id,
    String date = '2026-10-02',
  }) => repo.saveEntry(
    id: id,
    kind: EntryKind.reimburse,
    amount: amount,
    accountId: cash,
    debtAccountId: claims,
    date: date,
  );
  Future<String> receipt(
    String debt,
    int amount, {
    String date = '2026-10-03',
  }) => repo.saveEntry(
    kind: EntryKind.reimbursement,
    amount: amount,
    accountId: cash,
    debtId: debt,
    date: date,
  );
  Future<String> invest(
    EntryKind kind,
    int amount, {
    String? id,
    String? productId,
    String date = '2026-10-02',
  }) => repo.saveEntry(
    id: id,
    kind: kind,
    amount: amount,
    accountId: cash,
    targetAccountId: investment,
    investmentProductId: productId ?? product,
    unitPrice: '12.345678',
    date: date,
  );

  test('partial reimbursement preserves assets, excludes income expense, SQL and Dart agree', () async {
    final id = await claim();
    await receipt(id, 600);
    final balances = await repo.balances();
    expect(balances[cash], 99100);
    expect(balances[claims], 900);
    final entries = await db.select(db.entries).get();
    for (final a in await db.select(db.accounts).get()) {
      expect(
        a.openingBalance +
            entries.fold<int>(0, (s, e) => s + accountEntryDelta(a, e)),
        balances[a.id],
      );
      final view = await LedgerReadRepository(db)
          .account((id: a.id, month: null, kind: '', search: '', limit: 100));
      expect(
        a.openingBalance + view.transactions + view.corrections,
        balances[a.id],
      );
    }
    final report = await StatisticsRepository(db)
        .load(ReportRange.at(ReportPeriod.month, DateTime(2026, 10)), 'CNY');
    expect(report.income, 0);
    expect(report.expense, 0);
    await receipt(id, 900);
    expect((await repo.balances())[claims], 0);
    await expectLater(receipt(id, 1), throwsFormatException);
  });
  test('reimbursement rejects overpayment, backdating, wrong account and unsafe principal changes', () async {
    final id = await claim();
    await receipt(id, 500);
    await expectLater(receipt(id, 1001), throwsFormatException);
    await expectLater(
      receipt(id, 1, date: '2026-10-01'),
      throwsFormatException,
    );
    await expectLater(claim(id: id, amount: 499), throwsFormatException);
    await expectLater(claim(id: id, date: '2026-10-04'), throwsFormatException);
    await expectLater(repo.deleteEntry(id), throwsFormatException);
    await expectLater(
      repo.saveEntry(
        kind: EntryKind.reimburse,
        amount: 1,
        accountId: cash,
        debtAccountId: investment,
        date: '2026-10-01',
      ),
      throwsFormatException,
    );
    expect((await repo.balances())[claims], 1000);
  });
  test('product cost isolation, redeem directions, no estimate, edit and delete rollback', () async {
    final buy = await invest(EntryKind.invest, 10000);
    final sell = await invest(EntryKind.redeem, 3000, date: '2026-10-03');
    expect((await repo.balances())[cash], 93000);
    expect((await repo.balances())[investment], 7500);
    final rows = await db.select(db.entries).get();
    expect(rows.first.unitPrice, '12.345678');
    for (final a in await db.select(db.accounts).get()) {
      final view = await LedgerReadRepository(db)
          .account((id: a.id, month: null, kind: '', search: '', limit: 100));
      expect(
        a.openingBalance + view.transactions,
        (await repo.balances())[a.id],
      );
      expect(
        a.openingBalance +
            rows.fold<int>(0, (s, e) => s + accountEntryDelta(a, e)),
        (await repo.balances())[a.id],
      );
    }
    await expectLater(
      invest(EntryKind.redeem, 7001, date: '2026-10-04'),
      throwsFormatException,
    );
    await expectLater(
      invest(EntryKind.invest, 2000, id: buy),
      throwsFormatException,
    );
    await expectLater(repo.deleteEntry(buy), throwsFormatException);
    final other = await repo.saveInvestmentProduct(
      accountId: investment,
      name: '另一个产品',
      kind: '基金',
    );
    await expectLater(
      invest(EntryKind.redeem, 1, productId: other),
      throwsFormatException,
    );
    await expectLater(
      invest(EntryKind.redeem, 1, date: '2026-10-01'),
      throwsFormatException,
    );
    await expectLater(
      repo.deleteInvestmentProduct(product),
      throwsFormatException,
    );
    await repo.deleteEntry(sell);
    await repo.deleteEntry(buy);
    await repo.deleteInvestmentProduct(product);
  });
  test('credit limit validates separately from balance and investment currency is enforced', () async {
    final credit = await repo.saveAccount(
      name: '合成信用卡',
      kind: '信贷账户',
      channel: '信用卡',
      currency: 'CNY',
      openingBalance: -2000,
      creditLimit: 8000,
    );
    expect((await repo.balances())[credit], -2000);
    expect(
      (await (db.select(
        db.accounts,
      )..where((a) => a.id.equals(credit))).getSingle()).creditLimit,
      8000,
    );
    await expectLater(
      repo.saveAccount(
        name: '错误额度',
        kind: '资金账户',
        channel: '现金',
        currency: 'CNY',
        openingBalance: 0,
        creditLimit: 1,
      ),
      throwsFormatException,
    );
    await expectLater(
      repo.saveAccount(
        name: '负额度',
        kind: '信贷账户',
        channel: '信用卡',
        currency: 'CNY',
        openingBalance: 0,
        creditLimit: -1,
      ),
      throwsFormatException,
    );
    final foreign = await repo.saveAccount(
      name: '外币',
      kind: '资金账户',
      channel: '现金',
      currency: 'USD',
      openingBalance: 0,
    );
    await expectLater(
      repo.saveEntry(
        kind: EntryKind.invest,
        amount: 1,
        accountId: foreign,
        targetAccountId: investment,
        investmentProductId: product,
        date: '2026-10-02',
      ),
      throwsFormatException,
    );
  });
  test('backup round trip retains claims, products, price and credit; account deletion cascades products', () async {
    await repo.saveAccount(
      name: '合成信用卡',
      kind: '信贷账户',
      channel: '信用卡',
      currency: 'CNY',
      openingBalance: -500,
      creditLimit: 6000,
    );
    final debt = await claim();
    await receipt(debt, 500);
    await invest(EntryKind.invest, 900);
    final dir = await Directory.systemTemp.createTemp('finance_backup_');
    final target = AppDatabase(NativeDatabase.memory());
    try {
      final bytes = await BackupService(db, MediaStore(dir)).export();
      await BackupService(target, MediaStore(dir)).restore(bytes);
      expect(await LedgerRepository(target).balances(), await repo.balances());
      expect(
        (await target.select(target.investmentProducts).get()).single.name,
        '合成产品',
      );
      expect(
        (await target.select(target.entries).get())
            .where((e) => e.kind == 'invest')
            .single
            .unitPrice,
        '12.345678',
      );
      expect(
        (await target.select(target.accounts).get())
            .where((a) => a.kind == '信贷账户')
            .single
            .creditLimit,
        6000,
      );
      await LedgerRepository(target).deleteAccount(investment);
      expect(await target.select(target.investmentProducts).get(), isEmpty);
      expect(
        await target.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    } finally {
      await target.close();
      await dir.delete(recursive: true);
    }
  });
}
