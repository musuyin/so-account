import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/features/updates/data/app_updates.dart';
import 'package:so_account/features/updates/presentation/update_controller.dart';
import 'package:so_account/features/updates/presentation/update_page.dart';

class PreviewUpdates extends UpdateController {
  PreviewUpdates({required bool isAndroid}) {
    supported = true;
    android = isAndroid;
    currentVersion = '0.4.0';
    currentBuild = 4;
    update = AppUpdate(
      version: '0.5.0',
      build: 5,
      notes: List.filled(15, '新增应用内更新，可下载与安装。').join('\n'),
      apk: UpdateAsset(
        Uri.parse(
          'https://github.com/musuyin/so-account/releases/download/v0.5.0/SoAccount-v0.5.0-android.apk',
        ),
        80000000,
      ),
      sha256Hex: '0' * 64,
    );
  }
  @override
  Future<void> initialize() async {}
}

void main() {
  for (final android in [true, false]) {
    testWidgets('update page at 320px and large text, android=$android', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = PreviewUpdates(isAndroid: android);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [updateControllerProvider.overrideWithValue(controller)],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const UpdatePage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('前往 GitHub Release'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (android) {
        await tester.scrollUntilVisible(
          find.text('下载更新包'),
          -200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('下载更新包'), findsOneWidget);
      } else {
        expect(find.text('下载更新包'), findsNothing);
        expect(find.textContaining('iOS 无法安装 APK'), findsOneWidget);
      }
    });
  }
}
