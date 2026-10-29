# v1.5.0 验证记录

实施日期：2026-10-28；公开发布验收：2026-10-29。版本：v1.5.0 / 1.5.0+20，Schema 9。

本次增加清空本地业务数据、完全重置软件、输入文字确认、全屏导航隔离、提交前回滚、文件清理中断恢复及后台更新协调。具体操作范围见 [本地数据管理](../product/local-data-management.md)。

## 本地检查

发布版本 1.5.0+20 的 303 项 Flutter 测试、17 项 Python 构建工具测试、格式检查、静态分析与数据库生成一致性检查通过；Windows 本机跳过 1 项符号链接创建用例，须在 Linux CI 单独确认。另将实际文件库明确设为 WAL 模式复测清空、重置和恢复，6 项通过、同一符号链接用例跳过。Android 调试构建及固定签名的正式通用、ARM64、ARM32、x86_64 包均通过，四个正式包的版本/build 为 1.5.0/20，签名与 v1.4.0 相同。本地通用包 SHA-256：`8b70979f2ac810c5a4ce6df9eb0bbdef509a21c8846d9459413a5921a2480b71`；公开包另行核对，不假定不同主机构建逐字节一致。

新增验证覆盖关联业务表、分类与外观设置保留、当前默认分类初始化、关闭重开后旧分类不回填、原 SQLite/WAL 旧业务内容清理、事务回滚、文件删除失败与恢复、本机清理凭据不导出、路径越界与目录重叠保护、取消／错误确认不删除、全屏导航隔离、页面状态刷新、后台更新退出等待，以及 320 像素／1.6 倍字体浅深色实际截图。

CI 测试输出留存步骤显式使用 bash 的 pipefail 行为，测试失败会阻止打包和发布。

## CI 和公开发布

发布源码：`e1a355d7334f6e0a390e11a17c612ab43bb19466`，标签 `v1.5.0`。

- [正式发布流水线 40691318812](https://github.com/musuyin/so-account/actions/runs/40691318812) 成功：304 项 Flutter 测试、17 项 Python 工具测试、静态分析、固定签名通用及三架构正式 APK 构建通过。
- [Mobile checks 40691317615](https://github.com/musuyin/so-account/actions/runs/40691317615) 成功：Linux Android 检查中 304 项 Flutter 测试通过，包含 Windows 跳过的替换媒体根目录符号链接保护用例；17 项 Python 工具测试、Android 调试构建和 iOS 模拟器构建通过。`device-recovery` 任务跳过，不计为设备验收。
- CI 留存 `release-ui-evidence`（12817502271）、`release-build-logs`（12817862237）、`android-ui-evidence`（12816599316）、`android-build-logs`（12818200748）及 `android-debug-apk`（12818240773）。
- [公开 Release](https://github.com/musuyin/so-account/releases/tag/v1.5.0) 为正式最新版，20 个资产包含通用及三架构 APK、更新清单、校验和与 v1.3.0/v1.4.0 增量包。四个 APK 及增量包的清单、大小、SHA-256 与 GitHub 资产摘要一致。
- 实际下载公开 ARM64 APK，包名 `dev.soaccount.so_account`、版本 `1.5.0`、build `20`，SHA-256 为 `50ffecd1b115627138047ecc5eb6dcdffca72cc5637b06e2189ff6300b4fa050`。正式签名与 v1.4.0 一致，证书 SHA-256 为 `f0db22ad213879a06fcc7e55a40dd80fa230725ab52f230e77c5d55fd1469634`。包内包含本地清理逻辑。
- 实际下载 v1.4.0 ARM64 对应增量包，使用旧公开 APK 重建；结果与上述 v1.5.0 公开签名包逐字节摘要一致。
- 使用实际 `AppUpdateService` 联网验证：build 19 能发现 1.5.0/build 20，通用及三架构选择正确；从旧公开 ARM64 APK 成功下载差分并合成校验，未回退整包；build 20 返回已是最新版。该检查运行在主机客户端，不代表手机系统安装验收。

结构化证据见 [public-release.json](evidence/v1.5.0/public-release.json)。

## 设备边界

未执行 Android/iOS 真机清空与重置、进程强杀后的清理恢复、覆盖安装及跨版本数据保留验收。模拟文件失败和数据库重开不等同于真机验收。iOS CI 仅验证模拟器构建。
