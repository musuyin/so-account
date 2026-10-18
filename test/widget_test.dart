import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/app/theme/app_theme.dart';

void main() {
  testWidgets('warm and dark themes render', (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(brightness),
          home: const Scaffold(body: Text('拾账')),
        ),
      );
      expect(find.text('拾账'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
