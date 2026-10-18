# so-account · 素帐

Flutter + Dart 的个人记账与物品管理应用，Android / iOS 共享代码，SQLite 本地优先，无后端、登录或云同步。当前名称“素帐”和应用标识 `dev.soaccount.so_account` 用于开发版本。

## 已实现

- 月历主页、日筛选、备注 / 账户搜索、类型和分类筛选，按币种呈现月收入、支出、结余及预算。
- 收入、支出、同币种转账、借入、借出、偿还借入、收回借出；新增、编辑、删除及余额联动。
- 银行卡、微信、支付宝、现金等渠道；资金、充值、信贷、理财账户；独立币种及初始余额。
- 自定义收支分类、分类统计、近六个月趋势及未结清往来。
- 物品独立登记、搜索 / 分类、购入价与日期、照片 / 拍照、日均使用成本，以及购买支出的多物品关联与双向查看。
- 全量 / 指定月 / 指定年 CSV 明细，月 / 年按分类及币种汇总；保存与系统分享。
- 包含照片、账户和全部关联的 ZIP 完整备份，摘要与隔离校验、确认后事务替换恢复。
- 暖白日间 / #121212 深色 / 跟随系统外观；内置开源中文字体。

## 验证状态

Windows 本地已通过 `flutter analyze`、19 项自动测试和 Android debug / release APK 构建。测试覆盖金额与日期、真实 SQLite、余额与借贷约束、关闭重开持久化、物品关联、CSV、备份回滚、媒体清理，以及明暗主题下 390 / 320 像素和放大文字的页面。

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

本次安装的本地 SDK 在 `.tooling/flutter`，未改系统 PATH。此工作区可用 `.\.tooling\flutter\bin\flutter.bat` 代替上述 `flutter`。开发工具与个人运行数据均不提交。APK 位于 `build/app/outputs/flutter-apk/`：`app-debug.apk` 为调试包，`app-release.apk` 为约 72 MB 的优化测试包。两者均使用开发签名，仅用于自行安装测试，尚未配置应用商店发布签名。

## 使用与边界

先在“账户”添加一个账户，再从主页“记一笔”。点日期查看当天流水，点流水编辑；从支出“记物”或独立进入“物品”。在“设置”管理分类、导出 CSV、完整备份和恢复。

默认人民币，支持 CNY / USD / EUR / GBP / JPY / HKD。币种分别统计，不隐含汇率，跨币种转账暂不支持。借贷本金不计收支，需记录还款才会结清。物品价格独立维护，不自动分摊整笔购买金额。每件物品当前支持一张照片。

备份不加密；恢复为全量替换。压缩文件上限 50 MB、展开上限 100 MB、最多 1000 张照片。当前仅实现 Schema / 备份版本 1。大数据量和进程强杀恢复仍需真机验证。

## 文档

- [实施规则](docs/product/implementation-decisions.md)
- [产品需求](docs/product/requirements.md)
- [技术选型](docs/engineering/technology.md)
- [目录与边界](docs/engineering/architecture.md)
- [数据规则](docs/engineering/data-design.md)
- [备份协议](docs/engineering/backup-format.md)
- [环境设置](docs/engineering/setup.md)
- [交付与真机验收](docs/engineering/roadmap.md)
