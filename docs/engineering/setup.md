# 环境与开发

## 本次已验证环境

2026-10-18，Windows 11：Flutter stable 3.47.7（abaf9c5237）、Dart 3.13.5、JDK 17.0.12、Android SDK platform 36 / build-tools 36.0.0。构建过程按插件要求另行安装了 platform 35、CMake 3.22.1 及 Flutter 对应 NDK。Gradle wrapper 9.3.1、Android Gradle Plugin 9.1.0、Kotlin 2.4.0 由此 Flutter 模板生成。

Flutter 位于 `.tooling/flutter`，Android SDK 位于 `.tooling/android-sdk`，Gradle 缓存在 `.tooling/gradle`，这些目录全部忽略。没有将 Flutter / Dart 添加到全局 PATH。Flutter 本机配置记录了 Android SDK 和 `D:\Coding\Java\jdk17`；其他电脑应使用自己的路径。

## 新环境

按 Flutter 官方指南安装指定 stable SDK 和 Android SDK / JDK，连接开启 USB 调试的手机并授权。然后执行：

```powershell
flutter --version
flutter doctor -v
flutter doctor --android-licenses
flutter pub get --enforce-lockfile
dart run build_runner build
flutter analyze
flutter test
flutter devices
flutter run -d <device-id>
```

本工作区可以使用 `.\.tooling\flutter\bin\flutter.bat`。若直接使用 Dart，路径为 `.tooling/flutter/bin/cache/dart-sdk/bin/dart.exe`。

```powershell
$env:ANDROID_HOME = "$PWD\.tooling\android-sdk"
$env:JAVA_HOME = 'D:\Coding\Java\jdk17'
$env:GRADLE_USER_HOME = "$PWD\.tooling\gradle"
.\.tooling\flutter\bin\flutter.bat build apk --debug
```

Android 项目关闭 Kotlin 增量编译，解决 Windows 的插件缓存位于 C 盘、工程位于 D 盘时相对路径跨盘失败。Gradle wrapper 与 jar 需要随代码提交；不是私有机器配置。

## 数据库生成

```powershell
dart run build_runner build
dart run drift_dev schema dump lib/data/database/app_database.dart lib/data/database/migrations
```

提交生成的 `.g.dart`、Schema 快照和依赖锁。新增 Schema 版本时同时写迁移及旧库升级测试；当前为 v9，保留 v1–v8 升级路径。v9 新增账户归档状态，详见 [账户归档与永久删除](../product/account-archive.md)。

## 设备与 iOS

```powershell
flutter test integration_test/persistence_test.dart -d <android-device-id>
```

设备测试添加唯一名称的合成账户和支出，关闭并重新打开数据库后检查持久化，再清理测试数据；不清空现有库。它只验证数据库连接重开，不替代 Android 应用进程重启验收。

在 Mac 上安装同版 Flutter / Xcode / CocoaPods（插件需要时），执行 `flutter doctor -v`、`flutter pub get --enforce-lockfile`、`flutter build ios --simulator --debug`，再完成 iPhone 图片、文件分享和恢复验收。应用权限说明已包含相机与照片。

GitHub Actions 提供 Android 分析、测试、生成一致性及 APK；另有 macOS iOS 模拟器构建。请以实际 workflow 结果为准。

依据：[Flutter 安装](https://docs.flutter.dev/install/manual)、[Android 环境](https://docs.flutter.dev/platform-integration/android/setup)、[Drift 安装](https://drift.simonbinder.eu/setup/)。
