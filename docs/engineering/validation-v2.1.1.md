# v2.1.1 验证记录

日期：2026-11-04。版本：2.1.1+29，Schema 11。

## 范围

- 移除月历图例、图表操作提示、空状态副说明，以及常用表单、导出和更新页面的冗余说明。
- 理财和报销管理新增顶部货币按钮，以平铺芯片直接选择；只展示所选币种的账户和条目，新建表单继承当前币种。关闭选择面板不修改币种。
- 当前资产、统计图表、物品日均和借贷结算金额不再重复显示单位；余额核对和归档账户使用顶部货币选择隔离内容。多币种导入预览和导出文件保留辨别币种所需的信息。
- 数据库、资产和负债口径、金额隐私、归档限制及删除确认沿用现有行为。

## 验证

- 新增界面回归覆盖四种配色的浅深模式、320 像素和 1.6 倍文字、带返回按钮的真实导航布局，验证 CNY/USD/JPY 切换、空币种、日元精度、取消、表单继承及金额隐私。
- 月历保留色阶、今日和选中标记与日期过滤。已有日期测试改为选择非今天的有流水日期，避免每月 4 日将当前选择取消。
- 静态分析、全库格式检查及 17 项 Python 工具测试通过。完整 Flutter 回归 395 项通过，Windows 跳过 1 项既有符号链接用例。最终正式签名 APK 构建通过，包名、版本 2.1.1、build 29 和固定签名已核对。
- 截图使用合成数据，不包含参考图中的真实账户和金额。已目检并保留[月历](evidence/v2.1.1/calendar-light-320.png)、[理财](evidence/v2.1.1/investment-light-320.png)、[报销](evidence/v2.1.1/reimbursement-dark-320.png)、[货币选择](evidence/v2.1.1/currency-picker-dark-320.png)、统计环形图[浅色](evidence/v2.1.1/category-light-320.png)与[深色](evidence/v2.1.1/category-dark-320.png)、[余额核对](evidence/v2.1.1/balance-review.png)。
- 本次未进行真机覆盖安装及数据保留验收。

## 发布

发布源码：`3faa8bcb4769ccea3cd59db58f7381692abea82a`，标签 `v2.1.1`。

- [正式发布工作流](https://github.com/musuyin/so-account/actions/runs/41750598668)成功；[Mobile checks](https://github.com/musuyin/so-account/actions/runs/41750594067)的 Android 和 iOS 模拟器构建成功。两条工作流的源码 SHA 与发布源码一致。
- 已读取发布及 Android 作业日志，两者均为 396 项 Flutter 测试、17 项 Python 测试、静态分析通过；Android 作业同时完成数据库生成一致性检查。正式签名通用包及 ARM64 / ARM32 / x86_64 包构建、签名和增量还原检查全部通过。
- CI 截图保存在 release-ui-evidence（13286225080）和 android-ui-evidence（13286350558）。
- [公开 Release](https://github.com/musuyin/so-account/releases/tag/v2.1.1)已核对为 latest，20 个附件完整；更新清单、校验和、四个 APK 及全部补丁的大小和摘要与 GitHub 资产一致。
- 已下载公开 ARM64 APK，核对版本 `2.1.1+29`、包名和上一版正式签名一致；下载的 v2.1.0 ARM64 增量补丁可精确还原新版 APK。结构化结果见 [public-release.json](evidence/v2.1.1/public-release.json)。
