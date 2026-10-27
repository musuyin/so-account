# 结构与边界

当前为单个 Flutter 应用，按功能组织目录，SQLite 数据库共享。

```text
lib/
  main.dart
  app/                         主题、导航、provider 装配、通用页面组件
  core/money/                  纯 Dart 金额解析与显示
  core/time/                   本地业务日期与持有天数
  data/database/               Drift 表、连接、生成代码与 Schema 快照
  features/
    ledger/                    收支、转账、借贷、账户仓库与月历 / 表单
    inventory/                 物品、购买关联的事务写入及物品页面
    statistics/                SQL 聚合、CSV、分类 / 趋势 / 往来展示
    backup/                    纯编解码协议、校验恢复服务与备份页面
    settings/                  外观、分类与导出入口
    importing/                 Excel/CSV 读取、映射、预览与导入工作流
    goals/                     心愿、攒钱及独立进度记录
    updates/                   更新发现、下载、校验、差分与安装入口
  platform/
    media/                     私有图片、选择 / 恢复、延迟清理
    files/                     系统文件读取 / 保存 / 分享
test/                          规则、真实 SQLite、备份失败路径与页面
integration_test/              数据库重开、独立强杀恢复包及 profile 性能入口
benchmark/                     显式运行的主机 SQLite 基准，不计入普通测试
tool/                          构建/发布工具、Android 恢复宿主驱动
android/                       Android 平台工程及 Gradle wrapper
ios/                           iOS 平台工程与图片权限说明
```

页面通过仓库处理业务写入，不直接操作 SQL / 文件。provider 装配仓库和平台服务；Drift 记录在展示与数据层之间共享，不额外复制同构 DTO。纯 domain / core 规则不依赖 Flutter。简单 CRUD 不再创建空转发接口层；组合写入在共享数据库事务内执行。

统计和 CSV 汇总通过 SQL。首页按币种、月份、日期、类型、分类和搜索读取可见流水；日历每日总量与月汇总独立于分页。账户明细在 SQL 中限定账户/日期/类型/搜索，余额组成与筛选汇总覆盖完整范围。两页按 `(date, createdAt, id)` 倒序读取默认 100 条的前缀，点击更多增加 100 条；每次写入重新读取当前前缀，避免页间编辑/删除造成重复或遗漏。相关引用、聚合与明细在同一读事务内完成；不以独立到达的流拼接恢复前后记录。

应用根组件只订阅偏好表。其他页面和编辑器仍可订阅同一读事务产生的全量 `AppSnapshot`；全量流无消费者后释放。首页不订阅目标、进度、偏好、余额调整等无关表，账户明细不订阅物品等无关表。余额和统计另外订阅 SQL 结果。

支出同时记物由 LedgerRepository 在共享数据库事务中编排：先保存支出，再调用 InventoryRepository 创建物品和购买关联；任一步失败全部回滚。独立物品保存及关联替换由 InventoryRepository 校验只有同币种支出可关联。EntryDraft 管理记账选择、方向转换和保存参数；ImportWorkflow 管理文件/映射/预览/提交/完成状态，仓库继续负责业务约束。预留的 purchase_links 空目录尚未成为单独模块，不将目录占位视为实现。

备份拥有整个数据快照与恢复事务，不逐页调用 controller。恢复阶段先在隔离 SQLite 运行仓库规则，实际提交保留原审计时间和 ID；协议详见 [完整备份](backup-format.md)。

主导航为账本、账户、物品、统计、设置。go_router 管理主入口；详情 / 编辑通过 Navigator 路由打开并持有当前记录 ID，读取最新仓库结果后写入；记录已被删除时保存失败并保留表单。空目录的 .gitkeep 仅用于既有骨架，不代表功能。
