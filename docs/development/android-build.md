# Android 插件解析与 CI 构建

固定工具链为 Flutter 3.47.7、JDK 17、Gradle 9.3.1、AGP 9.1.0。AGP 的官方兼容说明见 [Android 发布说明](https://developer.android.com/build/releases/agp-9-1-0-release-notes)。不要仅凭 `Plugin was not found` 就改动工具链版本。

2026-10-19 的远程 Android 任务在解析 `com.android.application.gradle.plugin:9.1.0` 时失败。相同配置先前成功，官方标记 POM 与实现 POM 的实时请求均返回 HTTP 200；现有日志不足以确认底层 HTTP 或 TLS 错误。iOS 任务已通过。

`android/settings.gradle.kts` 使用 Gradle 的 `resolutionStrategy.eachPlugin.useModule`，将 Android 应用插件直接映射到固定版本的 `com.android.tools.build:gradle`，省去额外的插件标记 POM 请求。仍从 Google/Maven 官方仓库解析，不引入第三方镜像。机制见 [Gradle 插件解析规则](https://docs.gradle.org/current/userguide/plugins_intermediate.html)。

CI 运行 `python3 tool/build_android.py`：执行带详细日志的 debug 构建；仅对识别出的依赖解析/网络下载错误最多尝试三次，间隔 10/20 秒，代码编译错误直接失败。不会删除全局缓存或跳过校验。每次构建日志写入 `.tooling/ci-logs/android-build-N.log`，通过 `android-build-logs` 工件上传，便于定位实际访问失败。

本地可直接执行 `flutter build apk --debug --verbose`；Python 包装器需要 Flutter 在 PATH 中。辅助脚本测试：`python3 -m unittest discover -s tool -p 'test_*.py'`。
