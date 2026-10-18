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
  platform/
    media/                     私有图片、选择 / 恢复、延迟清理
    files/                     系统文件读取 / 保存 / 分享
test/                          规则、真实 SQLite、备份失败路径与页面
integration_test/              设备数据库关闭重开持久化
android/                       Android 平台工程及 Gradle wrapper
ios/                           iOS 平台工程与图片权限说明
```

页面通过仓库处理业务写入，不直接操作 SQL / 文件。provider 装配仓库和平台服务；Drift 记录在展示与数据层之间共享，不额外复制同构 DTO。纯 domain / core 规则不依赖 Flutter。简单 CRUD 不再创建空转发接口层；组合写入在共享数据库事务内执行。

统计和 CSV 汇总通过 SQL；月历使用当前数据快照呈现日期标记。全量展示快照的多个表在同一读事务读取，避免恢复期间混合新旧数据。余额和统计单独订阅 SQL 结果，页面通过加载状态区分尚未返回的结果。

购买关系写入暂集中在 InventoryRepository：保存物品与更新全部关联同一事务，校验只有同币种支出能关联。预留的 purchase_links 空目录尚未成为单独模块，不将目录占位视为实现。

备份拥有整个数据快照与恢复事务，不逐页调用 controller。恢复阶段先在隔离 SQLite 运行仓库规则，实际提交保留原审计时间和 ID；协议详见 [完整备份](backup-format.md)。

主导航为账本、账户、物品、统计、设置。go_router 管理主入口；详情 / 编辑通过 Navigator 路由打开并持有当前记录 ID，读取最新仓库结果后写入；记录已被删除时保存失败并保留表单。空目录的 .gitkeep 仅用于既有骨架，不代表功能。
