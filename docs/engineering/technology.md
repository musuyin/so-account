# 技术选型

2026-10-18 已初始化实际工程，版本解析见 `pubspec.lock`。原先仅做准备的阶段已结束。

| 领域 | 当前实现 |
| --- | --- |
| 框架 / 语言 | Flutter stable 3.47.7 / Dart 3.13.5，Android / iOS |
| UI | Material 3，自定义暖白 / 深色主题，内置 Noto Sans SC（OFL 授权） |
| 持久化 | Drift 2.35.x、drift_flutter 0.3.1、SQLite；数据库唯一持久化来源 |
| 状态 | flutter_riverpod 3.4.3，手写 provider，数据库查询流驱动 UI |
| 导航 | go_router 16.3.0，主导航 ShellRoute；编辑页面使用 Navigator 路由 |
| 金额 | 最小货币单位整数，按十进制字符串解析；币种独立汇总 |
| 文件 / 日期 / ID | path_provider、path、intl、uuid |
| 图片 | image_picker，选择后复制到私有 media/，Android 丢失结果恢复 |
| 文件交付 | file_picker 13.1.0 保存 / 读取系统文件，share_plus 13.3.1 分享 |
| 明细导入 | XLSX ZIP/XML、只读 XLS BIFF8/CFB 解析、SpreadsheetML、html 解析文本型 XLS；隔离线程处理，独立夹具回归 |
| 备份 | archive 4.5.2 ZIP、crypto SHA-256、逻辑 JSON 快照、隔离 SQLite 验证、事务恢复 |
| 数据库生成 | drift_dev 2.35.x、build_runner；提交 .g.dart 与 Schema v1–v4 快照 |
| 测试 | flutter_test / integration_test；金额日期、SQLite、CSV、关联、恢复和页面 |
| 自动构建 | GitHub Actions 的 Android 检查 / APK 和 macOS iOS 模拟器构建配置 |

当前不使用 Freezed、代码生成 Riverpod、网络客户端或第二套持久化状态。统计采用 SQL 聚合；柱形、饼图和净资产曲线用 Flutter 组件及 CustomPainter 实现，未额外引入图表依赖。

依赖范围使用明确兼容约束，不使用 any；应用锁文件随提交固定实际解析。Flutter 升级和 Schema 升级应独立交付。最低系统版本由所锁 Flutter 和插件的交集决定，实际 Gradle / Xcode 工程为准；本机未完成双端最低版本真机覆盖。

[Flutter 架构建议](https://docs.flutter.dev/app-architecture/recommendations)、[Drift](https://drift.simonbinder.eu/setup/)、[Riverpod](https://riverpod.dev/docs/tutorials/first_app)、[go_router](https://pub.dev/packages/go_router)、[image_picker](https://pub.dev/packages/image_picker)、[archive](https://pub.dev/packages/archive)。

0.2.0 的资产、图表和归档新规则以 [产品调整](../product/revision-0.2.md) 为准。
