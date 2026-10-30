# v1.9.0 验证记录

日期：2026-10-30。版本 1.9.0+24，数据库 Schema 10，没有结构迁移。

## 发布范围

账单重复汇总清理，转账／投资金额表达，账户选择余额右对齐及正负配色，说明文案精简，上期收支紧邻对比，带外侧标签的环形图，单级类别 Excel／CSV 模板和命名空间／原生日期解析修复，回形针文档启动图标。

## 已有验证证据

- 完整 Flutter 回归：337 项通过，Windows 跳过 1 项既有符号链接用例；发布前检查及 CI 结果另行记录。
- 单级分类参考 Excel 在隔离内存数据库验证：2706 条来源记录，2690 条有效入库（331 条收入），10 条零金额、6 条空账户跳过。原文件、真实账户、分类、备注及金额不提交仓库。
- Excel／CSV 模板从应用下载、重新解析到收入／支出事务入库通过；附加字段不会被当成币种代码、手续费或额外交易。带前缀 XML 的共享字符串、公式拒绝、1904 日期系统拒绝及原生日期读入已验证。
- 已查看浅深主题、320／390 像素及放大字体的账单、账户选择、上期对比、环形图、导入页面和模板渲染截图。金额隐私同步隐藏选择列表数值、颜色及无障碍金额；点击分类与图表返回保留既有行为。
- 新图标源图保存在 `design/icons/paperclip-v1.png`，平台图标按现有 Android 密度和 iOS Contents 配置生成，不含透明通道。

## 发布检查

格式检查、静态分析及 17 项 Python 工具测试通过。发布前完整 Flutter 回归再次通过 337 项，Windows 跳过 1 项既有用例。Drift 生成前后数据库生成文件摘要一致。

通用、ARM64、ARM32、x86_64 四个正式 APK 构建通过，并逐包检查包名 `dev.soaccount.so_account`、版本 1.9.0/build 24 和固定签名。证书 SHA-256 `f0db22ad213879a06fcc7e55a40dd80fa230725ab52f230e77c5d55fd1469634` 与 v1.8.0 相同。包内 Excel 模板与源资产字节一致，启动图标与新图标解码像素一致。

本地通用 APK SHA-256 `030f44c820fc32069ce983a666f470c96ab41fa1c79ad03f3974cc29efe87f07`；Excel 模板 SHA-256 `6b8331fcfea6a070f1f4da1b95bf56aa177b54dd24c4c8749c9da020ba320050`。不同主机的 APK 构建摘要不假定相同。

## CI 与公开发布

发布源码 `4bb673d82ab01394b132d4d812579a7715cc8c1c`，标签 `v1.9.0`。已核对两条工作流的 head SHA 与成功状态。

- [发布流水线 40987067804](https://github.com/musuyin/so-account/actions/runs/40987067804) 成功：338 项 Flutter 测试、17 项 Python 测试、格式、静态分析、通用／三架构签名包、增量生成与正式发布全部通过。
- [Mobile checks 40987067916](https://github.com/musuyin/so-account/actions/runs/40987067916) 成功：Android 338 项测试含 Windows 跳过的符号链接用例、数据库生成检查与调试构建通过，iOS 模拟器构建通过；device-recovery 按配置跳过。
- 已通过 GitHub 连接读取发布与 Android 作业日志，确认 `+338: All tests passed!` 与 17 项 Python 测试。发布截图 artifact 为 `12947448122`，构建日志 artifact 为 `12946899545`。
- [公开 v1.9.0](https://github.com/musuyin/so-account/releases/tag/v1.9.0) 为正式最新版，共 20 个资产。更新清单、四个 APK 和全部增量文件的大小、SHA-256、校验和文件与 GitHub 资产摘要一致。
- 实际下载公开 ARM64 包：1.9.0/build 24，包名 `dev.soaccount.so_account`，35,736,954 字节，SHA-256 `cdbb9b14fa42775724ab8c1fbfd0415755a8daa96e73335fbf8bc986803878e4`。正式签名与 v1.8.0 相同；新图标解码像素与源图标一致，Excel 模板字节与源码资产一致。
- 实际下载 v1.8.0 ARM64 增量文件并重建，结果与公开新签名 APK 的摘要完全一致。
- 真实 AppUpdateService 联网验证通用／三架构选择：build 23 发现 build 24；ARM64 下载 4,220,688 字节的差分、合成和校验成功，没有整包回退；build 24 显示已是最新版。

结构化证据见 [public-release.json](evidence/v1.9.0/public-release.json)。

## 设备边界

尚未进行本版本 Android／iOS 真机交互、系统字体／主题切换、覆盖安装和跨版本数据保留验证。自动测试、渲染截图、CI 构建与公开安装包校验均不替代真机验收。
