# so-account

个人记账与物品管理移动应用，采用 Flutter + Dart、SQLite 本地优先方案。先交付 Android，具备 macOS / Xcode 环境后再适配 iOS。产品名称待定，`so_account` 仅作为工程名。

## 当前状态

本仓库处于技术准备阶段，已建立技术方案、模块边界与可被 Git 保留的目录骨架。尚未初始化 Flutter 平台工程，没有 Dart 入口、依赖清单、数据库或业务实现，当前不能编译运行。

## 文档入口

| 文档 | 内容 |
| --- | --- |
| [需求基线](docs/product/requirements.md) | PRD v0.1 范围、阶段与待确认事项 |
| [技术选型](docs/engineering/technology.md) | 主要依赖、理由、引入时机与版本策略 |
| [项目结构](docs/engineering/architecture.md) | 目录职责、依赖方向与模块协作 |
| [数据设计原则](docs/engineering/data-design.md) | 金额、日期、关联、图片与备份约束 |
| [环境与初始化](docs/engineering/setup.md) | Windows / Android 环境及后续初始化流程 |
| [开发路线](docs/engineering/roadmap.md) | 阶段顺序、验收与测试重点 |

## 核心技术方案

Flutter / Dart、Drift / SQLite、Riverpod、go_router。按功能模块组织，模块内分 presentation、domain、data；系统能力通过 platform 封装。复杂用例按需提取，不为每次 CRUD 增加一层空转发。

## 范围

完整 MVP 包括账目 CRUD 与统计、物品 CRUD 与图片、账目和物品关联、包含图片的完整备份恢复。登录、云同步、后端、桌面与 Web 不在当前范围内。

`lib/`、`test/`、`integration_test/` 和 `assets/` 内的 `.gitkeep` 只用于保留空目录。开始实现后可移除已非空目录中的占位文件。
