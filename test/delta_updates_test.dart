import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/features/updates/data/app_updates.dart';
import 'package:so_account/features/updates/data/delta_patch.dart';

class DeltaTransport implements UpdateTransport {
  final files = <String, List<int>>{};
  final requests = <String>[];
  @override
  Future<UpdateResponse> get(Uri uri) async {
    requests.add(uri.toString());
    final bytes = files[uri.toString()];
    return UpdateResponse(
      bytes == null ? 404 : 200,
      Stream.fromIterable([
        for (var i = 0; i < (bytes?.length ?? 0); i += 137)
          bytes!.sublist(i, (i + 137).clamp(0, bytes.length)),
      ]),
    );
  }

  @override
  void cancel() {}
}

void main() {
  late Directory root;
  late File base;
  late List<int> baseBytes, targetBytes, patchBytes;
  late DeltaTransport transport;
  late Map<String, dynamic> manifest, release;
  const prefix =
      'https://github.com/musuyin/so-account/releases/download/v0.6.0/';
  const full = 'SoAccount-v0.6.0-android.apk';
  late String patchName;
  String hash(List<int> bytes) => sha256.convert(bytes).toString();
  Map<String, dynamic> asset(String name, List<int> bytes) => {
    'name': name,
    'size': bytes.length,
    'digest': 'sha256:${hash(bytes)}',
    'browser_download_url': '$prefix$name',
  };
  setUp(() async {
    root = await Directory.systemTemp.createTemp('so_delta_');
    baseBytes = await File('test/fixtures/delta/base.bin').readAsBytes();
    targetBytes = await File('test/fixtures/delta/target.bin').readAsBytes();
    patchBytes = await File('test/fixtures/delta/update.sodelta').readAsBytes();
    base = await File('${root.path}/base.apk').writeAsBytes(baseBytes);
    patchName =
        'SoAccount-v0.6.0-from-v0.5.3-universal-${hash(baseBytes).substring(0, 12)}.sodelta';
    manifest = {
      'schema': 1,
      'package': updatePackage,
      'version': '0.6.0',
      'build': 9,
      'apk': full,
      'size': targetBytes.length,
      'sha256': hash(targetBytes),
      'patches': [
        {
          'algorithm': deltaAlgorithm,
          'target': full,
          'targetSha256': hash(targetBytes),
          'baseSha256': hash(baseBytes),
          'baseSize': baseBytes.length,
          'file': patchName,
          'size': patchBytes.length,
          'sha256': hash(patchBytes),
        },
      ],
    };
    release = {
      'tag_name': 'v0.6.0',
      'draft': false,
      'prerelease': false,
      'body': 'synthetic',
      'assets': [asset(full, targetBytes), asset(patchName, patchBytes)],
    };
    transport = DeltaTransport()
      ..files.addAll({
        '$prefix$full': targetBytes,
        '$prefix$patchName': patchBytes,
      });
  });
  tearDown(() => root.delete(recursive: true));
  test(
    'Python-generated delta reconstructs exact target on Dart worker isolate',
    () async {
      final out = '${root.path}/out.apk';
      await applyDeltaInBackground(
        basePath: base.path,
        patchPath: 'test/fixtures/delta/update.sodelta',
        outputPath: out,
        baseHash: hash(baseBytes),
        targetHash: hash(targetBytes),
        targetSize: targetBytes.length,
      );
      expect(await File(out).readAsBytes(), targetBytes);
    },
  );
  test(
    'valid delta avoids full download and cleans intermediate files',
    () async {
      final update = AppUpdate.parse(release, manifest);
      final stages = <String>[];
      final output = await AppUpdateService(transport).download(
        update,
        Directory('${root.path}/cache'),
        installedApk: base,
        cancelled: () => false,
        onProgress: (_, _) {},
        onStage: stages.add,
      );
      expect(await output.readAsBytes(), targetBytes);
      expect(transport.requests, ['$prefix$patchName']);
      expect(stages.any((s) => s.contains('合成')), isTrue);
      expect((await output.parent.list().toList()).length, 1);
    },
  );
  for (final invalid in ['base', 'patch', 'command']) {
    test('$invalid mismatch falls back to verified full APK', () async {
      if (invalid == 'base') await base.writeAsBytes([1, 2, 3]);
      if (invalid == 'patch') transport.files['$prefix$patchName'] = [1, 2, 3];
      if (invalid == 'command') {
        final corrupt = [...patchBytes];
        corrupt[0] = 0;
        transport.files['$prefix$patchName'] = corrupt;
        (manifest['patches'] as List).single['sha256'] = hash(corrupt);
        (release['assets'] as List)[1] = asset(patchName, corrupt);
      }
      final output = await AppUpdateService(transport).download(
        AppUpdate.parse(release, manifest),
        Directory('${root.path}/cache'),
        installedApk: base,
        cancelled: () => false,
        onProgress: (_, _) {},
      );
      expect(await output.readAsBytes(), targetBytes);
      expect(transport.requests.last, '$prefix$full');
      expect((await output.parent.list().toList()).length, 1);
    });
  }
  test('cancelled delta never starts full fallback or publishes APK', () async {
    var cancelled = false;
    final cache = Directory('${root.path}/cache');
    await expectLater(
      AppUpdateService(transport).download(
        AppUpdate.parse(release, manifest),
        cache,
        installedApk: base,
        cancelled: () => cancelled,
        onProgress: (received, _) {
          if (received > 0) cancelled = true;
        },
      ),
      throwsA(isA<HttpException>()),
    );
    expect(transport.requests, ['$prefix$patchName']);
    expect(await cache.list().toList(), isEmpty);
  });
  test(
    'prefers supported ABI and keeps legacy universal manifest compatible',
    () {
      const name = 'SoAccount-v0.6.0-arm64-v8a.apk';
      manifest['variants'] = [
        {
          'abi': 'arm64-v8a',
          'apk': name,
          'size': targetBytes.length,
          'sha256': hash(targetBytes),
        },
      ];
      (release['assets'] as List).add(asset(name, targetBytes));
      expect(
        AppUpdate.parse(
          release,
          manifest,
          abis: ['arm64-v8a', 'armeabi-v7a'],
        ).abi,
        'arm64-v8a',
      );
      expect(AppUpdate.parse(release, manifest).abi, 'universal');
      expect(
        AppUpdate.parse(
          release,
          manifest,
          abis: ['unknown'],
        ).apk.uri.toString(),
        '$prefix$full',
      );
    },
  );
  test('rejects invalid delta metadata, source URLs and ABI names', () {
    final patch = (manifest['patches'] as List).single;
    patch['baseSize'] = -1;
    expect(() => AppUpdate.parse(release, manifest), throwsFormatException);
    patch['baseSize'] = baseBytes.length;
    (release['assets'] as List)[1]['browser_download_url'] =
        'https://example.com/update.sodelta';
    expect(() => AppUpdate.parse(release, manifest), throwsFormatException);
  });
  test('bounds checks reject output bombs, invalid copy ranges and trailing commands', () async {
    final header = Uint8List.fromList(patchBytes.take(88).toList());
    final number = ByteData(12)
      ..setUint64(0, baseBytes.length - 1, Endian.little)
      ..setUint32(8, 4096, Endian.little);
    for (final body in [
      [0, ...number.buffer.asUint8List(), 255],
      [2],
      [255, 1],
      [1, 255, 255, 255, 127],
    ]) {
      final patch = await File('${root.path}/bad.patch')
          .writeAsBytes([...header, ...gzip.encode(body)]);
      final output = File('${root.path}/bad.apk');
      await expectLater(
        applyDelta(
          base: base,
          patch: patch,
          output: output,
          baseHash: hash(baseBytes),
          targetHash: hash(targetBytes),
          targetSize: targetBytes.length,
        ),
        throwsFormatException,
      );
      expect(await output.exists(), isFalse);
    }
  });
}
