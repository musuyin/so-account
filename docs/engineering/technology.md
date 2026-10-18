# 技术选型

状态：工程准备基线。核对日期：2026-10-14。以下是针对本项目的方案选择，依赖版本与最低系统版本尚未经过本机解析及构建验证。

## 核心方案

| 领域 | 选型 | 理由与边界 | 引入阶段 |
| --- | --- | --- | --- |
| 框架 / 语言 | Flutter stable + 配套 Dart | 同一套移动端 UI 与业务代码；不单独升级 Dart 到不匹配的版本 | 初始化 |
| UI | Flutter Material 3 | 使用内置组件起步，后续调整主题；品牌与导航仍待设计 | Phase 1 |
| 本地数据库 | SQLite + `drift`、`drift_flutter` | 关系、事务、聚合查询、响应式查询与版本化迁移适合账目和物品 | Phase 1 |
| 状态 / 依赖装配 | `flutter_riverpod` | 统一异步状态和生命周期，通过 provider 装配仓库；使用稳定 API | Phase 1 |
| 导航 | `go_router` | 集中定义页面与详情路由，以记录 ID 传递定位信息 | Phase 1 |
| 金额 | 最小货币单位整数 | 存储和统计避免浮点误差，不依赖货币计算包 | Phase 1 |
| 文件目录 / 路径 | `path_provider`、`path` | 获取应用私有目录，避免绝对路径与平台路径分隔符写入业务数据 | Phase 1 / 2 |
| 本地 ID | `uuid` | 为记录和媒体生成稳定、不依赖设备的 ID；不代表已经设计云同步 | Phase 1 |
| 日期与金额显示 | `intl` | 中文日期和金额展示；不用于浮点金额计算 | Phase 1 |
| 静态检查 | `flutter_lints` | 采用 Flutter 常规检查基线 | 初始化 |
| 数据库代码生成 | `drift_dev`、`build_runner` | 仅 Drift 先使用生成器，Schema 迁移随变更提交 | Phase 1 |
| 测试 | `flutter_test`、`integration_test`（SDK） | 核心规则、SQLite 集成、关键设备流程 | 随实现引入 |

Riverpod 初期采用手写 provider、Notifier / AsyncNotifier，不引入 `riverpod_generator`。数据库是业务数据的唯一持久化来源；不使用 Riverpod 的实验性离线持久化作为第二套数据库。不预先添加 Freezed、复杂 DI 框架、网络客户端或多环境构建体系。

## 按需选型

| 能力 | 候选 | 当前处理 |
| --- | --- | --- |
| 图片选择 / 拍摄 | `image_picker` | Phase 2 引入；获取后复制到私有目录，处理权限拒绝和 Android 进程重建 |
| 趋势与占比图 | `fl_chart` | Phase 1 统计先完成数值与查询，图表确定后再验证该候选 |
| 完整备份容器 | `archive` | Phase 4 验证 ZIP 编解码、文件级流式处理和资源限制 |
| 校验摘要 | `crypto` | Phase 4 用 SHA-256 检查包内文件完整性；不是加密或身份认证 |
| 外部文件选择 / 保存 / 分享 | `file_selector` / `file_picker` / `share_plus` | Phase 4 在 Android 真机验证导入、导出；必要时组合使用，不假定各平台保存接口完全一致 |
| 备份加密 | 未定 | 由产品需求决定，再单独选择加密格式和密钥方案 |

不为预留功能提前安装依赖。尤其是文件导入 / 导出，需验证取消操作、文件 URI、系统文档提供器与大文件行为，再固定实现。

## 版本与可复现性

- 安装时选择 Flutter stable 的具体版本，记录 `flutter --version` 的完整输出；后续升级作为独立变更处理。
- 当前 PATH 未检测到 Flutter / Dart，暂不创建无法解析验证的 `pubspec.yaml` 或伪造 `pubspec.lock`。
- 初始化时用所选 SDK 解析兼容的稳定包版本，在 `pubspec.yaml` 中保留明确约束并提交应用的 `pubspec.lock`；禁止使用 `any`。
- Drift 运行库与生成器按同一发行系列升级；生成文件策略：提交 `.g.dart` 和 Schema 快照，检查可再生成一致性。
- 最低 Android / iOS 版本取 Flutter 与已采用插件要求的交集，再核对实际手机；此时不写未经验证的系统版本数字。
- FVM 是后续可选工具；单人起步先记录 SDK，不额外增加版本管理依赖。

## 依据

本项目采用 Flutter 官方建议的 UI / 数据分离与仓库边界，并按项目规模只提取必要的 domain 规则。这是项目裁剪后的方案，不照搬完整架构模板。

- [Flutter 架构建议](https://docs.flutter.dev/app-architecture/recommendations)
- [Drift 安装与生成器](https://drift.simonbinder.eu/setup/)
- [Drift 原生平台支持](https://drift.simonbinder.eu/platforms/vm/)
- [Riverpod 官方入门](https://riverpod.dev/docs/tutorials/first_app)
- [go_router 官方包](https://pub.dev/packages/go_router)
- [image_picker 官方包与平台注意事项](https://pub.dev/packages/image_picker)
- [archive 包文档](https://pub.dev/packages/archive)

这些文档支持能力判断；具体组合的可用性仍需初始化和真机构建验证。
