# 环境与后续初始化

## 当前检查

2026-10-14 检查当前命令行 PATH，未找到 `flutter`、`dart`。这不证明电脑上完全没有安装 SDK。仓库尚无 Flutter 工程，因此未执行依赖解析、静态分析、编译或真机测试。

本阶段不安装 SDK、不下载依赖、不生成业务代码。后续初始化按下列流程进行。

## Windows / Android 环境

- 按 [Flutter 官方安装指南](https://docs.flutter.dev/install/manual) 安装 stable SDK，并将 `bin` 加入 PATH。
- 配置 Android Studio、Android SDK、构建工具及 Flutter 所需 JDK，以所选 Flutter 的诊断结果为准。
- 在 Android 手机开启开发者模式和 USB 调试，连接并接受设备授权。
- 运行 `flutter --version`、`flutter doctor -v`、`flutter doctor --android-licenses`、`flutter devices`；记录实际工具版本及诊断结果，解决 Android 相关问题。
- Windows 可以开发 Android 和共享 Dart 代码；iOS 的构建、签名、模拟器及真机验证留到 macOS / Xcode 环境。

## 初始化步骤

1. 确认长期使用的组织标识和 Android application ID。产品名可以后改，但标识应在正式使用前稳定。`so_account` 是工程名，不是已确定的品牌。
2. 在临时目录用官方 CLI 创建 Android 模板，再将所需文件合入当前仓库；不要直接覆盖现有 README、LICENSE、文档和目录骨架，也不要复制模板的计数器演示及示例测试作为产品功能。
3. 命令形态如下，`<org_identifier>` 在执行前替换为已确认值，临时目录不能预先包含用户文件：

   ```powershell
   flutter create --platforms=android --project-name so_account --org <org_identifier> <temporary_directory>
   ```

4. 使用 SDK 生成的约束建立 `pubspec.yaml`，按 technology.md 的引入阶段增加依赖。先解析兼容版本，提交真实 `pubspec.lock`，记录 Flutter / Dart 版本。
5. 引入 SDK 的 `flutter_lints`、移除示例页面后建立最小应用入口；这属于下一阶段的代码工作。
6. 添加 Drift 时再配置生成器、Schema 导出与迁移；不为还不存在的表生成文件。
7. 完成 `flutter pub get`、`flutter analyze`、已有测试、Android debug 构建及真机启动验证。

## 初始化后的常用检查

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

添加 Drift 定义后才执行 `dart run build_runner build`。存在设备集成测试后，使用 `flutter test integration_test -d <device_id>`；启动应用使用 `flutter run -d <device_id>`。

## iOS 准备

获得 macOS / Xcode 后，用当时已记录的 Flutter 版本生成 iOS 工程，配置 Bundle ID、签名及图片权限文案，再验证所用插件与完整备份迁移。此前只能以跨平台 API 和目录边界减少耦合，不能宣称已完成 iOS 验证。

## 版本控制

保留官方生成的 Gradle wrapper 等平台构建文件；提交应用锁文件与必要生成源码。忽略 SDK 缓存、构建产物、私有签名材料、本机路径、真实数据库和备份。不要把用户照片作为静态资源或测试样例提交。
