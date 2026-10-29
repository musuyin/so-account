import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/app/providers/providers.dart';
import 'package:so_account/app/theme/app_theme.dart';
import 'package:so_account/core/appearance.dart';
import 'package:so_account/features/settings/presentation/settings_page.dart';

void main() {
  testWidgets(
    'four plain palettes and fields render at narrow width and large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await (FontLoader(
          'NotoSansSC',
        )..addFont(rootBundle.load('assets/fonts/NotoSansSC.ttf'))).load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      });
      final boundary = GlobalKey();
      Future<void> capture(String name) async {
        await tester.pump();
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('.tooling/screenshots').create(recursive: true);
          await File('.tooling/screenshots/$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      final data = AppSnapshot([], [], [], [], [], [], []);
      for (final palette in AppPalette.values) {
        for (final brightness in Brightness.values) {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                snapshotProvider.overrideWith((ref) => Stream.value(data)),
                preferencesProvider.overrideWith(
                  (ref) => Stream.value(data.preferences),
                ),
              ],
              child: MaterialApp(
                theme: appTheme(brightness, palette: palette),
                home: RepaintBoundary(
                  key: boundary,
                  child: const SettingsPage(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('绿色'), findsOneWidget);
          await capture('settings-${palette.name}-${brightness.name}');
        }
      }
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            snapshotProvider.overrideWith((ref) => Stream.value(data)),
            preferencesProvider.overrideWith(
              (ref) => Stream.value(data.preferences),
            ),
          ],
          child: MaterialApp(
            theme: appTheme(Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(1.8)),
              child: child!,
            ),
            home: RepaintBoundary(key: boundary, child: const SettingsPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('深色'), 200);
      expect(tester.takeException(), isNull);
      await capture('settings-large-text');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      for (final brightness in Brightness.values) {
        final focus = FocusNode();
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(brightness),
            home: RepaintBoundary(
              key: boundary,
              child: Scaffold(
                appBar: AppBar(title: const Text('绿色')),
                body: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    const Card(
                      borderOnForeground: false,
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('本月结余'),
                            SizedBox(height: 12),
                            Text('2,680.00', style: TextStyle(fontSize: 32)),
                            SizedBox(height: 28),
                            Text('收支有序，生活从容'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      focusNode: focus,
                      decoration: const InputDecoration(
                        labelText: '备注',
                        hintText: '记录夏日的小事',
                      ),
                    ),
                    const SizedBox(height: 20),
                    const TextField(
                      maxLines: 4,
                      decoration: InputDecoration(labelText: '详细说明'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await capture('plain-${brightness.name}');
        focus.requestFocus();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture('plain-focused-${brightness.name}');
        await tester.pumpWidget(const SizedBox.shrink());
        focus.dispose();
      }
    },
  );
}
