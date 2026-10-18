# 项目结构与边界

## 组织方式

采用单个 Flutter 应用、按功能组织目录；模块内部再按职责分层。当前只创建目录与占位文件，下列文件名示例不表示已经存在实现。

```text
so-account/
  docs/
    product/                  需求基线
    engineering/              技术、架构、数据和开发流程
  lib/
    app/
      router/                 路由与导航装配
      theme/                  全局主题
      providers/              数据库、仓库、系统服务的依赖装配
    core/
      money/                  金额解析、校验、格式化边界
      time/                   业务日期、月份范围和时间约定
      errors/                 可被页面表达的通用失败类型
    data/
      database/
        tables/               Drift 表定义，按阶段增量增加
        migrations/           迁移策略与提交的 Schema 快照
    platform/
      storage/                私有目录与媒体文件操作
      media/                  图片选择、权限与平台生命周期处理
      files/                  外部文件导入、导出和分享适配
    features/
      ledger/                 账目
        presentation/
        domain/
        data/
      inventory/              物品，同样分三层
      statistics/             统计，同样分三层
      purchase_links/         购买关联，同样分三层
      backup/                 全量备份恢复，同样分三层
      settings/
        presentation/         触发备份恢复、版本展示，不重复实现备份逻辑
  assets/
    images/                   随应用打包的静态图片，不存用户照片
  test/
    core/
    features/
    data/database/
    fixtures/backup/          仅人工构造、无个人敏感数据的备份样例
  integration_test/           重启持久化、图片与恢复等关键流程
```

`lib/main.dart`、`lib/app/app.dart`、`pubspec.yaml`、`analysis_options.yaml` 以及 `android/` 将在 Flutter 初始化阶段生成。`ios/` 在获得 macOS 环境后生成并验证。不为 Web、Windows、Linux 或 macOS 桌面端创建工程。

## 层次职责

| 位置 | 职责 | 依赖约束 |
| --- | --- | --- |
| presentation | 页面、表单、筛选与加载 / 错误状态；Riverpod controller | 调用仓库接口或复杂用例，不操作 SQL、文件或插件 |
| domain | 业务模型、校验规则、仓库接口及必要的复杂用例 | 只依赖 Dart 和必要的纯 Dart 工具，不依赖 Flutter、Drift、Riverpod 或系统插件 |
| feature data | 仓库实现、查询与映射 | 实现 domain 接口，调用公共数据库或平台服务 |
| data/database | 单个共享数据库、表、索引、迁移 | 不依赖页面和 UI 状态；不按功能各建一套数据库 |
| platform | 文件、图片和系统能力适配 | 不包含账目统计、分类或关联金额规则 |
| app | 生命周期、主题、路由、provider 装配 | 连接实现与接口，避免承担业务规则 |
| core | 多个模块确实共享的规则 | 不变成杂物目录，不引用具体功能模块 |

数据流：页面事件 → controller → 仓库 / 用例 → SQLite 或系统适配；数据库查询流 → provider → 页面。页面局部输入状态可以保留在页面，不必全部进入全局 provider。

简单 CRUD 直接通过仓库接口执行。只有组合操作（如从账目创建并关联物品、完整恢复）或重复的业务规则才提取用例。不要求每个模块复制 DTO、entity、mapper 三套几乎相同的模型。

## 跨模块协作

- statistics 读取聚合查询结果，不从页面中的账目列表累计，也不维护另一份持久化总额。
- purchase_links 拥有“创建物品并关联支出”的组合操作；跨表写入在共享数据库事务中完成。两个模块的页面不互相调用 controller。
- backup 通过专门的数据快照 / 恢复入口覆盖整个数据库与媒体，不逐一调用 CRUD 来恢复。
- settings 负责触发备份服务和呈现进度；路由用 ID 定位详情，每次读取当前数据，处理记录已删除状态。
- 目录名称采用 `snake_case`。`ledger` 指财务账目，避免与 SQL transaction 的事务语义混淆。

## 导航准备

预留账目、物品、统计、设置入口：首页是否单独存在、底部导航数量及快捷录入方式仍由 UI 设计决定。详情 / 编辑页面用账目或物品 ID 作为参数。现在不固化路由表和导航组件。
