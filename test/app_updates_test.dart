import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/features/updates/data/app_updates.dart';
import 'package:so_account/features/updates/presentation/update_controller.dart';

const apkUrl =
    'https://github.com/musuyin/so-account/releases/download/v0.5.0/SoAccount-v0.5.0-android.apk';
const manifestUrl =
    'https://github.com/musuyin/so-account/releases/download/v0.5.0/so-account-update.json';
final bytes = utf8.encode('synthetic APK content');
Map<String, dynamic> manifest() => {
  'schema': 1,
  'package': updatePackage,
  'version': '0.5.0',
  'build': 5,
  'apk': 'SoAccount-v0.5.0-android.apk',
  'size': bytes.length,
  'sha256': sha256.convert(bytes).toString(),
};
Map<String, dynamic> release() => {
  'tag_name': 'v0.5.0',
  'draft': false,
  'prerelease': false,
  'body': '更新说明',
  'assets': [
    {
      'name': 'so-account-update.json',
      'size': 300,
      'browser_download_url': manifestUrl,
    },
    {
      'name': 'SoAccount-v0.5.0-android.apk',
      'size': bytes.length,
      'browser_download_url': apkUrl,
      'digest': 'sha256:${sha256.convert(bytes)}',
    },
  ],
};

class FakeTransport implements UpdateTransport {
  int calls = 0;
  Map<String, dynamic> releaseData = release(), manifestData = manifest();
  List<int> apkBytes = bytes;
  int apiStatus = 200, apkStatus = 200;
  @override
  Future<UpdateResponse> get(Uri uri) async {
    calls++;
    if (uri.host == 'api.github.com') {
      return UpdateResponse(
        apiStatus,
        Stream.value(utf8.encode(jsonEncode(releaseData))),
      );
    }
    if (uri.toString() == manifestUrl) {
      return UpdateResponse(
        200,
        Stream.value(utf8.encode(jsonEncode(manifestData))),
      );
    }
    return UpdateResponse(
      apkStatus,
      Stream.fromIterable([
        apkBytes.take(4).toList(),
        apkBytes.skip(4).toList(),
      ]),
    );
  }

  @override
  void cancel() {}
}

class TestController extends UpdateController {
  TestController(AppUpdateService service) : super(service: service);
  @override
  Future<void> initialize() async {
    supported = true;
    android = true;
    currentVersion = '0.4.0';
    currentBuild = 4;
  }
}

void main() {
  late FakeTransport transport;
  late AppUpdateService service;
  setUp(() {
    transport = FakeTransport();
    service = AppUpdateService(transport);
  });

  test('checks build number and preserves release notes', () async {
    final update = (await service.check(4))!;
    expect(update.build, 5);
    expect(update.notes, '更新说明');
    expect(await service.check(5), isNull);
    expect(await service.check(6), isNull);
  });
  test('repository with no release is not a download failure', () async {
    transport.apiStatus = 404;
    expect(await service.check(4), isNull);
  });
  test('rate limiting is explained and is never treated as latest', () async {
    transport.apiStatus = 403;
    await expectLater(service.check(4), throwsA(isA<HttpException>()));
  });
  test('rejects prerelease and absent manifest', () async {
    transport.releaseData['prerelease'] = true;
    await expectLater(service.check(4), throwsFormatException);
    transport.releaseData = release()..['assets'] = [];
    await expectLater(service.check(4), throwsFormatException);
  });
  test('rejects wrong package, tag, build, checksum and declared size', () {
    for (final change in [
      {'package': 'other.app'},
      {'version': '0.6.0'},
      {'build': 0},
      {'sha256': 'bad'},
      {'size': bytes.length + 1},
      {'schema': 2},
    ]) {
      expect(
        () => AppUpdate.parse(release(), manifest()..addAll(change)),
        throwsFormatException,
      );
    }
  });
  test('rejects digest different from GitHub asset digest', () {
    final data = release();
    (data['assets'] as List)[1]['digest'] = 'sha256:${'0' * 64}';
    expect(() => AppUpdate.parse(data, manifest()), throwsFormatException);
  });
  test('restricts asset URL to this repository and release over HTTPS', () {
    for (final url in [
      apkUrl.replaceFirst('https:', 'http:'),
      apkUrl.replaceFirst('musuyin', 'attacker'),
      apkUrl.replaceFirst('v0.5.0/', 'v0.4.0/'),
      apkUrl.replaceFirst('github.com', 'github.com.attacker.test'),
      apkUrl.replaceFirst('github.com', 'github.com:444'),
    ]) {
      expect(
        () => UpdateAsset.parse({
          'browser_download_url': url,
          'size': 20,
        }, 'v0.5.0'),
        throwsFormatException,
      );
    }
    expect(
      () => UpdateAsset.parse({
        'browser_download_url': apkUrl,
        'size': maximumApkBytes + 1,
      }, 'v0.5.0'),
      throwsFormatException,
    );
  });

  group('download', () {
    late Directory directory;
    late AppUpdate update;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'so-account-update-test-',
      );
      update = AppUpdate.parse(release(), manifest());
    });
    tearDown(() async => directory.delete(recursive: true));

    Future<File> download({
      bool Function()? cancelled,
      void Function(int, int)? progress,
    }) => service.download(
      update,
      directory,
      cancelled: cancelled ?? () => false,
      onProgress: progress ?? (_, _) {},
    );

    test(
      'reports progress and promotes only checksum-verified package',
      () async {
        final progress = <int>[];
        final file = await download(
          progress: (received, total) {
            expect(total, bytes.length);
            progress.add(received);
          },
        );
        expect(await file.readAsBytes(), bytes);
        expect(progress.last, bytes.length);
        expect(
          await File('${directory.path}/update.apk.part').exists(),
          isFalse,
        );
      },
    );
    test('wrong checksum deletes incomplete package', () async {
      transport.apkBytes = List.filled(bytes.length, 0);
      await expectLater(download(), throwsFormatException);
      expect(await directory.list().isEmpty, isTrue);
    });
    test('truncated and oversized response are discarded', () async {
      for (final content in [
        bytes.sublist(0, 5),
        [...bytes, 1],
      ]) {
        transport.apkBytes = content;
        await expectLater(download(), throwsFormatException);
        expect(await directory.list().isEmpty, isTrue);
      }
    });
    test('cancel midway cleans partial and retry succeeds', () async {
      var cancelled = false;
      await expectLater(
        download(
          cancelled: () => cancelled,
          progress: (_, _) => cancelled = true,
        ),
        throwsA(isA<HttpException>()),
      );
      expect(await directory.list().isEmpty, isTrue);
      expect(await (await download()).readAsBytes(), bytes);
    });
    test('HTTP errors are never saved as APK', () async {
      transport.apkStatus = 503;
      await expectLater(download(), throwsA(isA<HttpException>()));
      expect(await directory.list().isEmpty, isTrue);
    });
  });

  test('automatic checks once a day, manual check bypasses interval', () async {
    final controller = TestController(service);
    addTearDown(controller.dispose);
    await controller.check();
    final count = transport.calls;
    await controller.check();
    expect(transport.calls, count);
    await controller.check(manual: true);
    expect(transport.calls, count * 2);
    expect(controller.update?.version, '0.5.0');
  });
  test('disabled automatic check still allows manual check', () async {
    final controller = TestController(service);
    addTearDown(controller.dispose);
    await controller.setAutomatic(false);
    await controller.check();
    expect(transport.calls, 0);
    await controller.check(manual: true);
    expect(controller.update, isNotNull);
  });
  test('failed refresh preserves previously discovered update', () async {
    final controller = TestController(service);
    addTearDown(controller.dispose);
    await controller.check(manual: true);
    transport.apiStatus = 403;
    await controller.check(manual: true);
    expect(controller.update?.build, 5);
    expect(controller.message, contains('请求频繁'));
    expect(controller.busy, isFalse);
  });
}
