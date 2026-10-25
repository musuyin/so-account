import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/core/time/business_date.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/goals/data/goals_repository.dart';
import 'package:so_account/features/ledger/data/ledger_repository.dart';
import 'package:so_account/features/backup/data/backup_service.dart';
import 'package:so_account/features/backup/domain/backup_codec.dart';
import 'package:so_account/platform/media/media_store.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late AppDatabase db;
  late GoalsRepository repo;
  final today = dateKey(DateTime.now());
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = GoalsRepository(db);
  });
  tearDown(() => db.close());
  Future<String> create({int initial = 0, String kind = 'saving'}) => repo.save(
    name: '旅行基金',
    kind: kind,
    currency: 'CNY',
    target: 10000,
    initialSaved: initial,
  );
  Future<WishGoal> goal() async => (await db.select(db.wishGoals).get()).single;
  Future<List<GoalContribution>> records() =>
      db.select(db.goalContributions).get();

  test('initial savings, deposits and withdrawals never alter accounts, ledger or budget', () async {
    final ledger = LedgerRepository(db);
    final account = await ledger.saveAccount(
      name: '钱包',
      kind: '资金账户',
      channel: '现金',
      currency: 'CNY',
      openingBalance: 20000,
    );
    await ledger.setBudget(monthKey(DateTime.now()), 'CNY', 5000);
    final id = await create(initial: 1000);
    await repo.contribute(goalId: id, amount: 2000, date: today);
    await repo.contribute(goalId: id, amount: -500, date: today);
    expect(goalSaved(id, await records()), 2500);
    expect((await ledger.balances())[account], 20000);
    expect(await db.select(db.entries).get(), isEmpty);
    expect((await db.select(db.budgets).get()).single.amount, 5000);
  });
  test(
    'concurrent withdrawals cannot overdraw and failure is atomic',
    () async {
      final id = await create(initial: 10000);
      var failures = 0;
      await Future.wait(
        List.generate(2, (_) async {
          try {
            await repo.contribute(goalId: id, amount: -7000, date: today);
          } on FormatException {
            failures++;
          }
        }),
      );
      expect(failures, 1);
      expect(goalSaved(id, await records()), 3000);
      expect((await records()).length, 2);
    },
  );
  test(
    'invalid inputs, future or historically overdrawn records are rejected',
    () async {
      final id = await create(initial: 1000);
      for (final amount in [0, -1001, maximumGoalAmount + 1]) {
        await expectLater(
          repo.contribute(goalId: id, amount: amount, date: today),
          throwsFormatException,
        );
      }
      await expectLater(
        repo.contribute(goalId: id, amount: -100, date: '2020-01-01'),
        throwsFormatException,
      );
      await expectLater(
        repo.contribute(
          goalId: id,
          amount: 100,
          date: dateKey(DateTime.now().add(const Duration(days: 1))),
        ),
        throwsFormatException,
      );
      await expectLater(
        repo.contribute(goalId: id, amount: 100, date: '2026-02-30'),
        throwsFormatException,
      );
      await expectLater(
        repo.save(name: ' ', kind: 'wish', currency: 'CNY', target: 1),
        throwsFormatException,
      );
      await expectLater(
        repo.save(name: 'a', kind: 'wish', currency: 'XYZ', target: 1),
        throwsFormatException,
      );
      expect((await records()).length, 1);
    },
  );
  test('completed savings require target; wish can be fulfilled without creating a purchase', () async {
    final id = await create(initial: 1000);
    await expectLater(repo.setStatus(id, 'completed'), throwsFormatException);
    await repo.contribute(goalId: id, amount: 10000, date: today);
    await repo.setStatus(id, 'completed');
    await expectLater(
      repo.contribute(goalId: id, amount: -1, date: today),
      throwsFormatException,
    );
    await repo.setStatus(id, 'active');
    await repo.contribute(goalId: id, amount: -1000, date: today);
    await repo.setStatus(id, 'archived');
    await expectLater(
      repo.contribute(goalId: id, amount: 1, date: today),
      throwsFormatException,
    );
    final wish = await create(kind: 'wish');
    await repo.setStatus(wish, 'completed');
    expect(await db.select(db.entries).get(), isEmpty);
  });
  test('a stale currency on the contribution form cannot save a mislabelled amount', () async {
    final id = await create();
    await repo.save(
      id: id,
      name: '旅行',
      kind: 'saving',
      currency: 'JPY',
      target: 1000,
    );
    await expectLater(
      repo.contribute(
        goalId: id,
        amount: 100,
        date: today,
        expectedCurrency: 'CNY',
      ),
      throwsFormatException,
    );
    expect(await records(), isEmpty);
  });
  test('currency remains locked even when contributions return to zero; deleted goals cannot reappear', () async {
    final id = await create(initial: 1000);
    await repo.contribute(goalId: id, amount: -1000, date: today);
    await expectLater(
      repo.save(
        id: id,
        name: '旅行',
        kind: 'saving',
        currency: 'USD',
        target: 200,
      ),
      throwsFormatException,
    );
    await repo.delete(id);
    expect(await records(), isEmpty);
    await expectLater(
      repo.save(
        id: id,
        name: '旅行',
        kind: 'saving',
        currency: 'CNY',
        target: 200,
      ),
      throwsFormatException,
    );
    expect(await db.select(db.wishGoals).get(), isEmpty);
  });
  test(
    'removing a deposit cannot invalidate later withdrawal history',
    () async {
      final id = await create(initial: 1000);
      final deposit = (await records()).single;
      await repo.contribute(goalId: id, amount: -500, date: today);
      await expectLater(
        repo.deleteContribution(deposit.id),
        throwsFormatException,
      );
      final withdrawal = (await records()).singleWhere((r) => r.amount < 0);
      await repo.deleteContribution(withdrawal.id);
      await repo.deleteContribution(deposit.id);
      expect(goalSaved(id, await records()), 0);
    },
  );
  test('daily schedule uses calendar days, ceiling minor units and preserves overfunding', () async {
    await create(initial: 12000);
    final g = (await goal()).copyWith(
      target: 100,
      deadline: const Value('2026-10-23'),
    );
    expect(goalDailyAmount(g, 0, DateTime(2026, 10, 21, 23)), 34);
    expect(goalDailyAmount(g, 0, DateTime(2026, 10, 23)), 100);
    expect(goalDailyAmount(g, 0, DateTime(2026, 10, 24)), 0);
    expect(goalDailyAmount(g, 120, DateTime(2026, 10, 21)), 0);
  });
  test('backup roundtrip includes goals and history; bad history preserves live data', () async {
    final root = await Directory.systemTemp.createTemp('goals_backup_');
    try {
      final service = BackupService(db, MediaStore(root));
      final id = await create(initial: 1000);
      await repo.contribute(goalId: id, amount: -200, date: today, note: '修正');
      final backup = await service.export();
      await repo.delete(id);
      await service.restore(backup);
      expect(goalSaved(id, await records()), 800);
      expect((await goal()).name, '旅行基金');
      final files = decodeBackup(backup);
      final json =
          jsonDecode(utf8.decode(files['data.json']!)) as Map<String, dynamic>;
      (json['contributions'] as List).first['amount'] = -100;
      files['data.json'] = Uint8List.fromList(utf8.encode(jsonEncode(json)));
      await expectLater(
        service.restore(encodeBackup(files)),
        throwsFormatException,
      );
      expect(goalSaved(id, await records()), 800);
      json.remove('goals');
      json.remove('contributions');
      files['data.json'] = Uint8List.fromList(utf8.encode(jsonEncode(json)));
      await service.restore(encodeBackup(files));
      expect(await db.select(db.wishGoals).get(), isEmpty);
      expect(await records(), isEmpty);
    } finally {
      await root.delete(recursive: true);
    }
  });
  test(
    'schema 6 upgrades preserve financial data and create empty goal tables',
    () async {
      final root = await Directory.systemTemp.createTemp('goals_v6_');
      final file = File('${root.path}/old.sqlite');
      try {
        final old = AppDatabase(NativeDatabase(file));
        await LedgerRepository(old).saveAccount(
          name: '钱包',
          kind: '资金账户',
          channel: '现金',
          currency: 'CNY',
          openingBalance: 1234,
        );
        await old.customStatement('DROP TABLE goal_contributions');
        await old.customStatement('DROP TABLE wish_goals');
        await old.customStatement('ALTER TABLE accounts DROP COLUMN bank');
        await old.customStatement(
          'ALTER TABLE accounts DROP COLUMN is_archived',
        );
        await old.customStatement('PRAGMA user_version=6');
        await old.close();
        final next = AppDatabase(NativeDatabase(file));
        try {
          expect(
            (await next.select(next.accounts).get()).single.openingBalance,
            1234,
          );
          expect(await next.select(next.wishGoals).get(), isEmpty);
          expect(await next.select(next.goalContributions).get(), isEmpty);
        } finally {
          await next.close();
        }
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}
