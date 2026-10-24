# 素帐 · SoAccount

Flutter + Dart 的个人记账与物品管理应用，Android / iOS 共享代码，SQLite 本地优先，无后端、登录或云同步。应用中文名“素帐”，英文名“SoAccount”；应用标识 `dev.soaccount.so_account` 保持不变。

## 已实现

- 月历主页、日筛选、备注 / 账户搜索、类型和分类筛选，按币种呈现月收入、支出、结余及预算。
- 紧凑首屏、可收起月历、流水操作菜单和物品组合筛选；新增表单继承当前币种，预算输入错误可直接修正。
- 收入、支出、同币种转账、借入、借出、偿还借入、收回借出；新增、编辑、删除及余额联动。
- 资金、信贷、充值、投资理财、债务账户，按类型及类别分组汇总；独立币种、初始余额与自定义类别。投资记录买入成本和单价，不计算实时价格。
- 编辑账户可直接调整实际余额，保留独立调整记录，不生成交易、不影响收支预算；资产趋势从调整当天反映变化。
- 账户明细展示期初余额、交易净变动及余额调整组成；按月、类型、备注或对方账户筛选，可编辑流水并从指定账户快捷记账。
- 心愿与攒钱：目标金额、截止日、优先级、存入/取出、超额进度、完成/归档、搜索排序及独立 CSV 汇总/明细导出；进度不改变账户或收支，完整备份包含全部目标记录。
- 自定义收支分类、周 / 月 / 年 / 自定义统计、柱状图、分类饼图、环比同比及年度资产走势。
- 物品种类多选与自定义、列表照片、未使用 / 使用中 / 使用完状态、消耗品数量和单位、总买入价和日均合计，以及购买支出关联。
- Excel .xls / .xlsx / CSV 分步导入、列名与内容映射、缺失账户创建与自动关联、逐条预览筛选、重复提示、分币种汇总及整批事务保存。
- 账单仅导入收入、支出，提供收支 CSV 模板和缺失账户关联；零金额、空账户及非收支类型自动忽略。导入后可核对实际余额，使用独立调整记录校正，不生成交易流水。
- 人员往来归并为应收款、应付款或报销账户，旧数据自动迁移，保留逐笔借贷和还款关联；可在手动记账时选择原始借贷，当前导入不处理转账及借贷。
- 全量 / 指定月 / 指定年 CSV 明细，月 / 年按分类及币种汇总；保存与系统分享。
- 包含照片、账户和全部关联的 ZIP 完整备份，摘要与隔离校验、确认后事务替换恢复。
- GitHub Release 正式版检查与更新说明、可关闭的每日自动检查；按设备架构分发 APK，匹配旧包后下载差分并合成，失败回退整包；下载可取消和重试，摘要及签名校验后进入 Android 系统安装。
- 经典暖色 / 夏日黄瓜花配色，浅色统一 #F5F5F5 背景，独立选择日间 / 深色 / 跟随系统；内置开源中文字体。

## 验证状态

Windows 本地验证包括 `flutter analyze`、189 项 Flutter 自动测试及 14 项 Python 构建工具测试。测试覆盖金额与日期、真实 SQLite、余额与借贷约束、债务账户迁移、余额调整与冲突保护、关闭重开持久化、物品关联与多种类、历史数据库迁移、Excel / CSV 导入与回滚、缺失账户创建/取消、账户币种变更检查、备份、媒体清理、更新清单与来源/摘要/大小校验、差分精确合成及失败回退、下载取消与重试、自动检查间隔，以及两种配色的日夜模式下 390 / 320 像素和放大文字的页面。紧凑界面另覆盖六行月历首屏、同日大额收支、外币新增、预算输入修正、菜单筛选和删除确认。XLS 另有独立生成的 BIFF8 二进制夹具，验证中文、长字符串、迷你流、异常文件及从选择文件进入列名关联的完整路径。

未连接 Android 真机；设备持久化测试入口已提供，但尚未执行。iOS 工程和权限配置已生成，本机无法执行 Xcode 构建或 iPhone 验收。GitHub Actions 已实际跑通过 Android 检查与 APK、iOS 模拟器构建；每次版本验收仍以相应运行结果为准。

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

差分能力从 v0.6.0 提供，旧版本首次升级仍下载完整包。后续更新在当前安装包摘要与已发布补丁匹配时应用差分，最终合成的 APK 与正式完整包逐字节一致。发布保留兼容旧客户端的通用包，并提供三种架构包；差分大小随实际修改变化，不保证每次均有可用补丁。

备份不加密；恢复为全量替换。压缩文件上限 50 MB、展开上限 100 MB、最多 1000 张照片。数据库当前为 Schema v8，支持 v1–v7 升级及旧备份恢复。明细导入是追加操作，支持 Excel 97–2003 .xls、.xlsx 和 UTF-8 CSV，兼容 UTF-8/UTF-16 XML/HTML 表格型 XLS；含公式的单元格请先粘贴为值，密码文件需先解密。格式边界见[明细导入](docs/product/import.md)。大数据量和进程强杀恢复仍需真机验证。

## 文档

- [实施规则](docs/product/implementation-decisions.md)
- [产品需求](docs/product/requirements.md)
- [技术选型](docs/engineering/technology.md)
- [目录与边界](docs/engineering/architecture.md)
- [数据规则](docs/engineering/data-design.md)
- [备份协议](docs/engineering/backup-format.md)
- [环境设置](docs/engineering/setup.md)
- [交付与真机验收](docs/engineering/roadmap.md)
- [心愿单与攒钱](docs/product/wishlist.md)
- [账户明细](docs/product/account-activity.md)
- [紧凑界面与日常使用](docs/product/compact-ui.md)
- [应用更新与发布](docs/engineering/app-updates.md)

[0.2.0 调整与统计口径](docs/product/revision-0.2.md)

0.2.0 的资产、图表和归档新规则见 [产品调整](docs/product/revision-0.2.md)。

0.3.0 的当前规则见 [物品与主题调整](docs/product/revision-0.3.md)、[明细导入](docs/product/import.md)。

0.4.0 的分步导入、账户创建、常驻保存栏、预算进度、物品筛选排序与主题整理见 [体验优化](docs/product/revision-0.4.md)。
