# 素帐 · SoAccount

Flutter + Dart 的个人记账与物品管理应用，Android / iOS 共享代码，SQLite 本地优先，无后端、登录或云同步。应用中文名“素帐”，英文名“SoAccount”；应用标识 `dev.soaccount.so_account` 保持不变。

## 已实现

- 月历主页、日筛选、备注 / 账户搜索、类型和分类筛选，按币种呈现月收入、支出、结余及预算。
- 收入、支出、同币种转账、借入、借出、偿还借入、收回借出；新增、编辑、删除及余额联动。
- 银行卡、微信、支付宝、现金等渠道；资金、充值、信贷、理财账户；独立币种及初始余额。
- 自定义收支分类、周 / 月 / 年 / 自定义统计、柱状图、分类饼图、环比同比及年度资产走势。
- 物品种类多选与自定义、列表照片、未使用 / 使用中 / 使用完状态、消耗品数量和单位、总买入价和日均合计，以及购买支出关联。
- Excel .xls / .xlsx / CSV 分步导入、列名与内容映射、缺失账户创建与自动关联、逐条预览筛选、重复提示、分币种汇总及整批事务保存。
- 账单“收支类型”识别、双端账户转账导入和缺失账户创建；收支、转账分别提供 CSV 模板，转账手续费单独记支出。
- 人员往来独立于账户，按人查看借入、借出及剩余本金，逐笔还款；导入时明确区分信贷还款与人员还款，并选择原始借贷。
- 全量 / 指定月 / 指定年 CSV 明细，月 / 年按分类及币种汇总；保存与系统分享。
- 包含照片、账户和全部关联的 ZIP 完整备份，摘要与隔离校验、确认后事务替换恢复。
- GitHub Release 正式版检查与更新说明、每天一次的可关闭自动检查、应用内 APK 下载进度/取消/重试、摘要及签名校验后进入 Android 系统安装。
- 经典暖色 / 夏日黄瓜花配色，浅色统一 #F5F5F5 背景，独立选择日间 / 深色 / 跟随系统；内置开源中文字体。

## 验证状态

Windows 本地验证包括 `flutter analyze`、Flutter 自动测试及 9 项 Python 构建工具测试。测试覆盖金额与日期、真实 SQLite、余额与借贷约束、关闭重开持久化、物品关联与多种类、历史数据库迁移、Excel / CSV 导入与回滚、缺失账户创建/取消、账户币种变更检查、备份、媒体清理、更新清单与来源/摘要/大小校验、下载取消与重试、自动检查间隔，以及两种配色的日夜模式下 390 / 320 像素和放大文字的页面。XLS 另有独立生成的 BIFF8 二进制夹具，验证中文、长字符串、迷你流、异常文件及从选择文件进入列名关联的完整路径。

未连接 Android 真机；设备持久化测试入口已提供，但尚未执行。iOS 工程和权限配置已生成，本机无法执行 Xcode 构建或 iPhone 验收。GitHub Actions 配置了 Android 检查与 APK、iOS 模拟器构建；配置存在不代表远端运行已通过。

## 开发

锁定 Flutter **3.47.7** / Dart **3.13.5**，依赖解析结果见 `pubspec.lock`。

```powershell
flutter pub get --enforce-lockfile
dart run build_runner build
flutter analyze
flutter test
flutter run -d <android-device-id>
flutter build apk --debug
```

本次安装的本地 SDK 在 `.tooling/flutter`，未改系统 PATH。此工作区可用 `.\.tooling\flutter\bin\flutter.bat` 代替上述 `flutter`。开发工具与个人运行数据均不提交。APK 位于 `build/app/outputs/flutter-apk/`。调试包用于开发；v0.5.0 起正式包要求固定发布签名，缺少签名时不允许构建 Release。签名配置、GitHub Actions Secrets、版本与 tag 发布步骤见 [应用更新与发布](docs/engineering/app-updates.md)。

## 使用与边界

先在“账户”添加一个账户，再从主页“记一笔”。点日期查看当天流水，点流水编辑；从支出“记物”或独立进入“物品”。在“设置”管理收支分类与物品种类、导入 Excel / CSV 明细、导出 CSV、完整备份和恢复。

默认人民币，支持 CNY / USD / EUR / GBP / JPY / HKD。币种分别统计，不隐含汇率，跨币种转账暂不支持。借贷本金不计收支，需记录还款才会结清。物品价格独立维护，不自动分摊整笔购买金额。每件物品当前支持一张照片。

“设置 → 应用更新”可检查 [GitHub Release](https://github.com/musuyin/so-account/releases) 并下载新版 Android APK。系统安装需要用户确认；旧调试签名若与正式签名不同，必须先完整备份并保存到应用外，再手动迁移，不能直接覆盖。iOS 仅显示更新信息与发布链接。自动检查会连接 GitHub，不发送账本数据；网络不可达时可稍后重试。

备份不加密；恢复为全量替换。压缩文件上限 50 MB、展开上限 100 MB、最多 1000 张照片。数据库当前为 Schema v4，支持 v1–v3 升级及旧备份恢复。明细导入是追加操作，支持 Excel 97–2003 .xls、.xlsx 和 UTF-8 CSV，兼容 UTF-8/UTF-16 XML/HTML 表格型 XLS；含公式的单元格请先粘贴为值，密码文件需先解密。格式边界见[明细导入](docs/product/import.md)。大数据量和进程强杀恢复仍需真机验证。

## 文档

- [实施规则](docs/product/implementation-decisions.md)
- [产品需求](docs/product/requirements.md)
- [技术选型](docs/engineering/technology.md)
- [目录与边界](docs/engineering/architecture.md)
- [数据规则](docs/engineering/data-design.md)
- [备份协议](docs/engineering/backup-format.md)
- [环境设置](docs/engineering/setup.md)
- [交付与真机验收](docs/engineering/roadmap.md)
- [应用更新与发布](docs/engineering/app-updates.md)

[0.2.0 调整与统计口径](docs/product/revision-0.2.md)

0.2.0 的资产、图表和归档新规则见 [产品调整](docs/product/revision-0.2.md)。

0.3.0 的当前规则见 [物品与主题调整](docs/product/revision-0.3.md)、[明细导入](docs/product/import.md)。

0.4.0 的分步导入、账户创建、常驻保存栏、预算进度、物品筛选排序与主题整理见 [体验优化](docs/product/revision-0.4.md)。
