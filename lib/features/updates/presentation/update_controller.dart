import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/app_updates.dart';

final updateControllerProvider = Provider<UpdateController>((ref) {
  final controller = UpdateController();
  ref.onDispose(controller.dispose);
  return controller;
});

class UpdateController extends ChangeNotifier {
  UpdateController({AppUpdateService? service})
    : service = service ?? AppUpdateService(GitHubUpdateTransport());
  static const channel = MethodChannel('dev.soaccount/updates');
  final AppUpdateService service;
  Future<void>? _initializing;
  File? _settings;
  DateTime? _lastCheck;
  bool supported = false, android = false, automatic = true;
  bool checking = false, downloading = false, installing = false;
  bool _cancelled = false, _disposed = false;
  String currentVersion = '', message = '';
  int currentBuild = 0, received = 0, total = 0;
  AppUpdate? update;
  File? downloaded;
  File? installedApk;
  List<String> abis = const [];
  bool get busy => checking || downloading || installing;

  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    try {
      final info = await channel.invokeMapMethod<String, dynamic>('info');
      if (info == null) return;
      currentVersion = info['version'] as String;
      currentBuild = info['build'] as int;
      android = info['platform'] == 'android';
      abis = (info['abis'] as List? ?? []).cast<String>();
      if (android && info['splitApk'] != true && info['baseApk'] is String) {
        installedApk = File(info['baseApk'] as String);
      }
      supported = android || info['platform'] == 'ios';
      _settings = File(
        '${(await getApplicationSupportDirectory()).path}/updates.json',
      );
      if (await _settings!.exists()) {
        try {
          final saved = jsonDecode(await _settings!.readAsString()) as Map;
          automatic = saved['automatic'] != false;
          _lastCheck = DateTime.tryParse(saved['lastCheck'] as String? ?? '');
        } catch (_) {
          // A damaged update preference file must never block the ledger.
        }
      }
    } on MissingPluginException {
      // Desktop previews and widget tests have no mobile installer.
    } catch (_) {
      message = '无法读取应用版本，请重新打开应用后重试';
    } finally {
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _save() async {
    try {
      await _settings?.writeAsString(
        jsonEncode({
          'automatic': automatic,
          'lastCheck': _lastCheck?.toUtc().toIso8601String(),
        }),
        flush: true,
      );
    } catch (_) {
      message = '更新偏好保存失败，下次启动可能恢复默认设置';
    }
  }

  Future<void> setAutomatic(bool value) async {
    automatic = value;
    await _save();
    _notify();
  }

  Future<void> check({bool manual = false}) async {
    await initialize();
    if (_disposed || !supported || busy) return;
    if (!manual &&
        (!automatic ||
            (_lastCheck != null &&
                DateTime.now().difference(_lastCheck!) <
                    const Duration(hours: 24)))) {
      return;
    }
    checking = true;
    message = '正在检查更新…';
    _notify();
    try {
      final next = await service.check(currentBuild, abis: abis);
      if (next?.build != update?.build) downloaded = null;
      update = next;
      message = next == null ? '当前已是最新正式版本' : '发现新版本 ${next.version}';
    } catch (error) {
      message = _error(error);
    } finally {
      _lastCheck = DateTime.now();
      await _save();
      checking = false;
      _notify();
    }
  }

  Future<void> download() async {
    final release = update;
    if (release == null || busy || !android) return;
    downloading = true;
    _cancelled = false;
    received = 0;
    total = release.apk.size;
    downloaded = null;
    message = '正在下载，请保持应用打开';
    _notify();
    try {
      final cache = await getTemporaryDirectory();
      downloaded = await service.download(
        release,
        Directory('${cache.path}/app-updates'),
        cancelled: () => _cancelled,
        installedApk: installedApk,
        onStage: (stage) {
          message = stage;
          _notify();
        },
        onProgress: (received, total) {
          this.received = received;
          this.total = total;
          _notify();
        },
      );
      message = '下载完成，校验通过。点击安装更新。';
    } catch (error) {
      message = _cancelled ? '下载已取消，可重新下载' : _error(error);
    } finally {
      downloading = false;
      _notify();
    }
  }

  void cancel() {
    if (!downloading) return;
    _cancelled = true;
    service.transport.cancel();
  }

  Future<void> install() async {
    if (downloaded == null || busy) return;
    installing = true;
    _notify();
    try {
      if (!await downloaded!.exists() ||
          await downloaded!.length() != update!.apk.size ||
          (await sha256.bind(downloaded!.openRead()).first).toString() !=
              update!.sha256Hex) {
        downloaded = null;
        throw const FormatException('安装包已失效，请重新下载');
      }
      final result = await channel.invokeMethod<String>('install', {
        'path': downloaded!.path,
        'build': update!.build,
      });
      message = result == 'permission_required'
          ? '请允许“安装未知应用”，返回后再次点击“安装更新”'
          : '已打开系统安装界面；取消后可再次点击安装';
    } catch (error) {
      message = _error(error);
    } finally {
      installing = false;
      _notify();
    }
  }

  Future<void> openRelease() async {
    try {
      await channel.invokeMethod<void>('openRelease', {
        'url':
            update?.releaseUrl ??
            'https://github.com/$updateRepository/releases',
      });
    } catch (error) {
      message = _error(error);
      _notify();
    }
  }

  String _error(Object error) => switch (error) {
    PlatformException(:final message) => message ?? '无法打开系统安装界面',
    FormatException(:final message) => message,
    HttpException(:final message) => message,
    SocketException() || TimeoutException() => '无法连接 GitHub，请检查网络后重试',
    _ => '更新失败，请稍后重试或前往 GitHub Release 下载',
  };

  @override
  void dispose() {
    _disposed = true;
    _cancelled = true;
    service.transport.cancel();
    super.dispose();
  }
}
