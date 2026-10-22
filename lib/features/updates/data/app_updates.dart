import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'delta_patch.dart';

const updateRepository = 'musuyin/so-account';
const updatePackage = 'dev.soaccount.so_account';
const maximumApkBytes = 250 * 1024 * 1024;

class UpdatePatch {
  const UpdatePatch(this.asset, this.sha256Hex, this.baseHash, this.baseSize);
  final UpdateAsset asset;
  final String sha256Hex, baseHash;
  final int baseSize;
}

class UpdateAsset {
  const UpdateAsset(this.uri, this.size);
  final Uri uri;
  final int size;

  factory UpdateAsset.parse(Map<String, dynamic> asset, String tag) {
    final uri = Uri.parse(asset['browser_download_url'] as String);
    final prefix = '/$updateRepository/releases/download/$tag/';
    final size = asset['size'] as int;
    if (uri.scheme != 'https' ||
        uri.host != 'github.com' ||
        uri.hasPort ||
        uri.userInfo.isNotEmpty ||
        !uri.path.startsWith(prefix) ||
        size <= 0 ||
        size > maximumApkBytes) {
      throw const FormatException('更新文件来源或大小无效');
    }
    return UpdateAsset(uri, size);
  }
}

class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.build,
    required this.notes,
    required this.apk,
    required this.sha256Hex,
    this.patches = const [],
    this.abi = 'universal',
  });
  final String version, notes, sha256Hex;
  final int build;
  final UpdateAsset apk;
  final List<UpdatePatch> patches;
  final String abi;
  String get tag => 'v$version';
  String get releaseUrl =>
      'https://github.com/$updateRepository/releases/tag/$tag';

  factory AppUpdate.parse(
    Map<String, dynamic> release,
    Map<String, dynamic> manifest, {
    List<String> abis = const [],
  }) {
    final version = manifest['version'] as String;
    final build = manifest['build'] as int;
    var hash = manifest['sha256'] as String;
    if (manifest['schema'] != 1 ||
        manifest['package'] != updatePackage ||
        !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version) ||
        release['tag_name'] != 'v$version' ||
        release['draft'] != false ||
        release['prerelease'] != false ||
        build <= 0 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw const FormatException('更新版本信息无效');
    }
    var name = manifest['apk'] as String;
    if (name != 'SoAccount-v$version-android.apk') {
      throw const FormatException('更新包名称无效');
    }
    final assets = (release['assets'] as List).cast<Map<String, dynamic>>();
    UpdateAsset resolve(String name, dynamic size, dynamic digest) {
      final found = assets.where((a) => a['name'] == name).toList();
      if (found.length != 1 ||
          digest is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
        throw const FormatException('更新附件或摘要无效');
      }
      final asset = UpdateAsset.parse(found.single, 'v$version');
      if (size != asset.size ||
          (found.single['digest'] != null &&
              found.single['digest'] != 'sha256:$digest')) {
        throw const FormatException('更新包校验信息不一致');
      }
      return asset;
    }

    var apk = resolve(name, manifest['size'], hash);
    var abi = 'universal';
    final variants = (manifest['variants'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    if (variants.length > 3 ||
        variants.map((v) => v['abi']).toSet().length != variants.length) {
      throw const FormatException('架构更新清单无效');
    }
    for (final supported in abis) {
      final variant = variants.where((v) => v['abi'] == supported).firstOrNull;
      if (variant == null) continue;
      if (!['arm64-v8a', 'armeabi-v7a', 'x86_64'].contains(supported) ||
          variant['apk'] != 'SoAccount-v$version-$supported.apk') {
        throw const FormatException('架构更新包名称无效');
      }
      name = variant['apk'] as String;
      hash = variant['sha256'] as String;
      apk = resolve(name, variant['size'], hash);
      abi = supported;
      break;
    }
    final patches = <UpdatePatch>[];
    final declared = (manifest['patches'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    if (declared.length > 16) throw const FormatException('差分清单数量超限');
    for (final patch in declared) {
      if (patch['target'] != name || patch['algorithm'] != deltaAlgorithm) {
        continue;
      }
      final patchName = patch['file'] as String;
      final baseHash = patch['baseSha256'] as String;
      final baseSize = patch['baseSize'] as int;
      if (!RegExp(
            r'^SoAccount-v\d+\.\d+\.\d+-from-v\d+\.\d+\.\d+-(universal|arm64-v8a|armeabi-v7a|x86_64)-[a-f0-9]{12}\.sodelta$',
          ).hasMatch(patchName) ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(baseHash) ||
          baseSize <= 0 ||
          baseSize > maximumApkBytes ||
          patch['targetSha256'] != hash) {
        throw const FormatException('差分版本信息无效');
      }
      final asset = resolve(patchName, patch['size'], patch['sha256']);
      if (asset.size < apk.size) {
        patches.add(
          UpdatePatch(asset, patch['sha256'] as String, baseHash, baseSize),
        );
      }
    }
    return AppUpdate(
      version: version,
      build: build,
      notes: (release['body'] as String?)?.trim() ?? '',
      apk: apk,
      sha256Hex: hash,
      patches: patches,
      abi: abi,
    );
  }
}

class UpdateResponse {
  const UpdateResponse(this.status, this.body);
  final int status;
  final Stream<List<int>> body;
}

abstract class UpdateTransport {
  Future<UpdateResponse> get(Uri uri);
  void cancel();
}

/// No credentials are sent. Redirects may only target GitHub's HTTPS CDN.
class GitHubUpdateTransport implements UpdateTransport {
  final Set<HttpClient> _clients = {};

  @override
  Future<UpdateResponse> get(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    _clients.add(client);
    try {
      for (var redirects = 0; redirects < 6; redirects++) {
        if (uri.scheme != 'https' ||
            uri.hasPort ||
            uri.userInfo.isNotEmpty ||
            !{
              'api.github.com',
              'github.com',
              'release-assets.githubusercontent.com',
              'objects.githubusercontent.com',
            }.contains(uri.host)) {
          throw const FormatException('更新下载地址不受支持');
        }
        final request = await client
            .getUrl(uri)
            .timeout(const Duration(seconds: 25));
        request.followRedirects = false;
        request.headers.set(HttpHeaders.userAgentHeader, 'SoAccount-Updater');
        if (uri.host == 'api.github.com') {
          request.headers.set(
            HttpHeaders.acceptHeader,
            'application/vnd.github+json',
          );
          request.headers.set('X-GitHub-Api-Version', '2022-11-28');
        }
        final response = await request.close().timeout(
          const Duration(seconds: 25),
        );
        if ({301, 302, 303, 307, 308}.contains(response.statusCode)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null) throw const FormatException('下载跳转地址缺失');
          uri = uri.resolve(location);
          await response.drain<void>().timeout(const Duration(seconds: 25));
          continue;
        }
        Stream<List<int>> body() async* {
          try {
            yield* response.timeout(const Duration(seconds: 30));
          } finally {
            _clients.remove(client);
            client.close(force: true);
          }
        }

        return UpdateResponse(response.statusCode, body());
      }
      throw const FormatException('下载跳转次数过多');
    } catch (_) {
      _clients.remove(client);
      client.close(force: true);
      rethrow;
    }
  }

  @override
  void cancel() {
    for (final client in _clients) {
      client.close(force: true);
    }
    _clients.clear();
  }
}

class AppUpdateService {
  AppUpdateService(this.transport);
  final UpdateTransport transport;

  Future<Map<String, dynamic>?> _json(
    Uri uri, {
    bool allowMissing = false,
  }) async {
    final response = await transport.get(uri);
    if (response.status != 200) {
      // Close the response without buffering a possibly large error page.
      await response.body.take(1).drain<void>();
      if (allowMissing && response.status == 404) return null;
      throw HttpException(
        response.status == 403 || response.status == 429
            ? 'GitHub 请求频繁，请稍后重试'
            : '无法读取更新信息（HTTP ${response.status}）',
      );
    }
    final bytes = <int>[];
    await for (final part in response.body) {
      bytes.addAll(part);
      if (bytes.length > 1024 * 1024) {
        throw const FormatException('更新说明文件过大');
      }
    }
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  Future<AppUpdate?> check(
    int installedBuild, {
    List<String> abis = const [],
  }) async {
    final release = await _json(
      Uri.https('api.github.com', '/repos/$updateRepository/releases/latest'),
      allowMissing: true,
    );
    if (release == null) return null;
    if (release['draft'] != false || release['prerelease'] != false) {
      throw const FormatException('此版本不是正式发布版本');
    }
    final tag = release['tag_name'] as String;
    if (!RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(tag)) {
      throw const FormatException('发布版本号格式无效');
    }
    final manifests = (release['assets'] as List)
        .cast<Map<String, dynamic>>()
        .where((a) => a['name'] == 'so-account-update.json');
    if (manifests.length != 1) {
      throw const FormatException('此 Release 未提供应用更新清单');
    }
    final asset = UpdateAsset.parse(manifests.single, tag);
    final manifest = await _json(asset.uri);
    final update = AppUpdate.parse(release, manifest!, abis: abis);
    return update.build > installedBuild ? update : null;
  }

  Future<File> download(
    AppUpdate update,
    Directory directory, {
    required void Function(int received, int total) onProgress,
    required bool Function() cancelled,
    File? installedApk,
    void Function(String message)? onStage,
  }) async {
    await directory.create(recursive: true);
    final partial = File('${directory.path}/update.apk.part');
    final target = File('${directory.path}/update.apk');
    if (await target.exists()) await target.delete();
    final patchFile = File('${directory.path}/update.sodelta');
    try {
      if (installedApk != null &&
          update.patches.isNotEmpty &&
          await installedApk.exists()) {
        onStage?.call('正在核对已安装版本…');
        final basePath = installedApk.path;
        String? baseHash;
        var size = 0;
        try {
          baseHash = await hashApkInBackground(basePath);
          size = await installedApk.length();
        } on FileSystemException {
          // Some distribution channels do not expose a readable single APK.
        }
        final matches =
            update.patches
                .where((p) => p.baseHash == baseHash && p.baseSize == size)
                .toList()
              ..sort((a, b) => a.asset.size.compareTo(b.asset.size));
        if (cancelled()) throw const HttpException('下载已取消');
        if (matches.isNotEmpty) {
          final patch = matches.first;
          try {
            onStage?.call('正在下载差分补丁…');
            await _downloadVerified(
              patch.asset,
              patch.sha256Hex,
              patchFile,
              onProgress,
              cancelled,
            );
            if (cancelled()) throw const HttpException('下载已取消');
            onStage?.call('正在合成并校验安装包…');
            final patchPath = patchFile.path, outputPath = partial.path;
            await applyDeltaInBackground(
              basePath: basePath,
              patchPath: patchPath,
              outputPath: outputPath,
              baseHash: patch.baseHash,
              targetHash: update.sha256Hex,
              targetSize: update.apk.size,
            );
            if (cancelled()) throw const HttpException('下载已取消');
            return await partial.rename(target.path);
          } catch (_) {
            if (cancelled()) rethrow;
            if (await partial.exists()) await partial.delete();
            onStage?.call('差分不可用，正在下载完整更新包…');
          }
        }
      }
      if (cancelled()) throw const HttpException('下载已取消');
      onStage?.call('正在下载完整更新包…');
      await _downloadVerified(
        update.apk,
        update.sha256Hex,
        partial,
        onProgress,
        cancelled,
      );
      if (cancelled()) throw const HttpException('下载已取消');
      return await partial.rename(target.path);
    } finally {
      if (await patchFile.exists()) await patchFile.delete();
      if (await partial.exists()) await partial.delete();
    }
  }

  Future<void> _downloadVerified(
    UpdateAsset asset,
    String expectedHash,
    File partial,
    void Function(int, int) onProgress,
    bool Function() cancelled,
  ) async {
    IOSink? sink;
    var completed = false;
    try {
      if (cancelled()) throw const HttpException('下载已取消');
      final response = await transport.get(asset.uri);
      if (response.status != 200) {
        await response.body.take(1).drain<void>();
        throw HttpException('下载失败（HTTP ${response.status}），请重试');
      }
      sink = partial.openWrite();
      var received = 0;
      onProgress(0, asset.size);
      await for (final bytes in response.body) {
        if (cancelled()) throw const HttpException('下载已取消');
        received += bytes.length;
        if (received > asset.size) {
          throw const FormatException('安装包大小与发布信息不符');
        }
        sink.add(bytes);
        await sink.flush();
        onProgress(received, asset.size);
      }
      await sink.close();
      sink = null;
      if (cancelled()) throw const HttpException('下载已取消');
      if (received != asset.size ||
          (await sha256.bind(partial.openRead()).first).toString() !=
              expectedHash) {
        throw const FormatException('安装包校验失败，请重新下载');
      }
      completed = true;
    } finally {
      await sink?.close();
      if (!completed && await partial.exists()) await partial.delete();
    }
  }
}
