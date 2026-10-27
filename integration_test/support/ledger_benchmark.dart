import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:so_account/data/database/app_database.dart';
import 'package:so_account/features/ledger/data/ledger_read_repository.dart';
import 'package:so_account/platform/media/media_store.dart';

import 'recovery_fixture.dart';

class QueryCounter extends QueryInterceptor {
  int selects = 0;
  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    selects++;
    return executor.runSelect(statement, args);
  }
}

Future<Map<String, Object?>> runLedgerBenchmark({
  Future<Map<String, Object?>> Function(AppDatabase db, String account)? render,
}) async {
  final report = <String, Object?>{
    'os': Platform.operatingSystemVersion,
    'runtime': Platform.version,
    'fixture': 'synthetic-v1',
    'scenarios': <Object?>[],
  };
  final scenarios = report['scenarios']! as List<Object?>;
  for (final size in [1000, 10000, 100000]) {
    final root = await Directory.systemTemp.createTemp('so-benchmark-');
    final counter = QueryCounter();
    final db = AppDatabase(NativeDatabase.memory().interceptWith(counter));
    try {
      await seedRecoveryFixture(db, MediaStore(root));
      final wallet = (await db.select(db.accounts).get()).firstWhere(
        (a) => a.name == '合成钱包',
      );
      final watch = Stopwatch()..start();
      await db.batch(
        (batch) => batch.insertAll(db.entries, [
          for (var i = 0; i < size; i++)
            EntriesCompanion.insert(
              id: 'bench-$i',
              kind: 'expense',
              amount: 100 + i % 997,
              accountId: wallet.id,
              categoryId: const Value('expense-0'),
              date:
                  '2026-${(i % 12 + 1).toString().padLeft(2, '0')}-${(i % 28 + 1).toString().padLeft(2, '0')}',
              note: const Value('deterministic synthetic row'),
              createdAt: i,
              updatedAt: i,
            ),
        ]),
      );
      final importMs = watch.elapsedMicroseconds / 1000;
      final reads = LedgerReadRepository(db);
      final data = <String, Object?>{'rows': size, 'batchInsertMs': importMs};
      Future<void> measure(
        String name,
        Future<Object?> Function() action,
      ) async {
        await action(); // Warm caches; these are read latencies, not cold startup.
        counter.selects = 0;
        final times = <double>[];
        for (var i = 0; i < 10; i++) {
          final timer = Stopwatch()..start();
          await action();
          times.add(timer.elapsedMicroseconds / 1000);
        }
        times.sort();
        data[name] = {
          'p50Ms': times[4],
          'p95Ms': times[9],
          'selectsPerLoad': counter.selects / 10,
          'rssBytesAfter': ProcessInfo.currentRss,
          'processPeakRssBytes': ProcessInfo.maxRss,
        };
      }

      // The previous snapshot allocated every table on every invalidation.
      await measure(
        'previousFullSnapshot',
        () => db.transaction(() async {
          for (final table in db.allTables) {
            await db
                .customSelect('SELECT * FROM "${table.actualTableName}"')
                .get();
          }
          return null;
        }),
      );
      await measure(
        'month',
        () => reads.home((
          month: '2026-10',
          currency: 'CNY',
          day: null,
          kind: null,
          category: null,
          search: '',
          limit: 100,
        )),
      );
      await measure(
        'monthSwitch',
        () => reads.home((
          month: '2026-09',
          currency: 'CNY',
          day: null,
          kind: null,
          category: null,
          search: '',
          limit: 100,
        )),
      );
      await measure(
        'account',
        () => reads.account((
          id: wallet.id,
          month: '2026-10',
          kind: '',
          search: '',
          limit: 100,
        )),
      );
      data['queryPlan'] =
          (await db
                  .customSelect(
                    'EXPLAIN QUERY PLAN SELECT e.* FROM entries e JOIN accounts a ON a.id=e.account_id WHERE a.currency=? AND e.date>=? AND e.date<? ORDER BY e.date DESC,e.created_at DESC,e.id DESC LIMIT 100',
                    variables: [
                      const Variable('CNY'),
                      const Variable('2026-10-01'),
                      const Variable('2026-11-01'),
                    ],
                  )
                  .get())
              .map((r) => r.data)
              .toList();
      if (render != null) data['render'] = await render(db, wallet.id);
      scenarios.add(data);
    } finally {
      await db.close();
      await root.delete(recursive: true);
    }
  }
  return report;
}
