# v2.1.0 验证记录

版本 `2.1.0+28`，源码提交 `56373631363b5ce72938c7c9eb09ba3e3b6c901c`，标签 `v2.1.0`。数据库 Schema 11。

## 功能与数据

- 理财账户当前资产及更新时间单独保存，不影响买入成本、账户账面余额、收支、预算或资产统计。支持零值、重新更新与清除；取消不写入，非法金额保留输入并提示。账户归档后只读，记录现值后禁止改变币种和账户类型。
- 账户列表、详情和理财管理同时显示成本和当前资产。隐藏金额后现值也被遮蔽，详情的无障碍文本不暴露金额。
- 日历今天为常驻细框，选中日期为粗框，选中今天保留双框；收支热度和日期筛选行为保留。四种配色、浅深主题、320/390 像素及大字体由渲染测试覆盖。
- 记物排序以芯片直接选择，写入本地 `inventory_sort` 偏好；页面重开、数据库关闭重开及完整备份恢复后保留选择，并实际按选项排序。
- Schema 10 → 11 保留账户、产品、投资流水及余额，新字段默认空；既有历史升级测试更新夹具并通过。旧备份缺省字段兼容，新备份校验现值、时间及排序，损坏数据整批回滚。

## 本地验证

- 格式检查、`flutter analyze` 通过。
- 最终全量 Flutter 测试：375 通过、1 跳过；Python 构建工具测试：17 通过。
- 正式签名通用 APK 构建通过。包名 `dev.soaccount.so_account`，版本名 `2.1.0`、版本号 `28`；签名与 v2.0.2 相同，APK 中包含当前资产与排序偏好字段。
- 实际查看并保留合成数据渲染截图：[投资详情](evidence/v2.1.0/investment-detail-light-320.png)、[理财管理](evidence/v2.1.0/investment-management-dark-320.png)、[账户列表](evidence/v2.1.0/investment-list-light-320.png)、[今日细框](evidence/v2.1.0/calendar-today-light-320.png)、[选中今天双框](evidence/v2.1.0/calendar-today-selected-dark-320.png)、[记物排序](evidence/v2.1.0/inventory-sort-light.png)。

## CI 与发布

- [Mobile checks](https://github.com/musuyin/so-account/actions/runs/41633530878)：Android / iOS 均通过，CI 全量测试 376 项通过，数据库代码生成一致性检查、Android 构建及 iOS 模拟器构建均通过。
- [正式发布工作流](https://github.com/musuyin/so-account/actions/runs/41633972810)成功，通用包、三种 ABI、签名校验、更新清单及差分生成全部通过。
- [公开 Release](https://github.com/musuyin/so-account/releases/tag/v2.1.0)已确认为 latest，20 个附件完整，清单中的 APK / 补丁大小、SHA-256 与 GitHub 附件摘要一致。下载 ARM64 APK 验证版本 `2.1.0+28`、同一正式签名及新增字段；v2.0.2 ARM64 差分可精确还原新签名 APK。记录见 [公开附件验证](evidence/v2.1.0/public-release.json)。
- 使用应用自身更新客户端实测：build 27 能发现通用包和三种 ABI；ARM64 差分下载、合成及摘要验证通过，补丁 4,223,500 字节，目标 APK 35,802,642 字节；build 28 返回已是最新。

真机交互、系统覆盖安装和跨版本数据保留未在本次执行；自动化与模拟器构建结果不等同于真机验收。
