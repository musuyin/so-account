import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:so_account/app/providers/providers.dart';
import 'package:so_account/features/ledger/presentation/home_page.dart';
import 'package:so_account/features/ledger/presentation/account_detail_page.dart';

import 'support/ledger_benchmark.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('named Android profile target ledger measurements', (
    tester,
  ) async {
    expect(
      kProfileMode,
      isTrue,
      reason: 'Use flutter drive --profile on a named target',
    );
    final result = await runLedgerBenchmark(
      render: (db, account) async {
        final frames = <FrameTiming>[];
        void collect(List<FrameTiming> value) => frames.addAll(value);
        binding.addTimingsCallback(collect);
        final loads = <String, Object?>{};
        try {
          for (final page in [
            ('home', const HomePage()),
            ('account', AccountDetailPage(id: account)),
          ]) {
            final timer = Stopwatch()..start();
            await tester.pumpWidget(
              ProviderScope(
                key: UniqueKey(),
                overrides: [databaseProvider.overrideWithValue(db)],
                child: MaterialApp(home: page.$2),
              ),
            );
            await tester.pumpAndSettle();
            loads['${page.$1}FirstFrameMs'] = timer.elapsedMicroseconds / 1000;
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        } finally {
          binding.removeTimingsCallback(collect);
        }
        loads['frames'] = frames
            .map(
              (f) => {
                'buildUs': f.buildDuration.inMicroseconds,
                'rasterUs': f.rasterDuration.inMicroseconds,
              },
            )
            .toList();
        return loads;
      },
    );
    result['target'] = const String.fromEnvironment(
      'BENCHMARK_TARGET',
      defaultValue: 'unnamed',
    );
    result['mode'] = 'profile';
    binding.reportData = result;
  }, timeout: const Timeout(Duration(minutes: 10)));
}
