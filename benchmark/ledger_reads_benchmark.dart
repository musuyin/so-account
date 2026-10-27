import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/ledger_benchmark.dart';

void main() {
  test('host SQLite scoped-read benchmark', () async {
    final result = await runLedgerBenchmark();
    result['target'] = 'Windows flutter_tester; host evidence only';
    final output = File('.tooling/benchmarks/ledger-host.json');
    await output.parent.create(recursive: true);
    await output.writeAsString(
      const JsonEncoder.withIndent('  ').convert(result),
    );
  }, timeout: const Timeout(Duration(minutes: 10)));
}
