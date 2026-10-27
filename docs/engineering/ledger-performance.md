# 账本读取基准

实现只限制首页与账户明细的 SQL 读取范围和默认 100 条可见前缀，不改变数据库 Schema v9。每次增加 100 条并以唯一排序重读当前前缀，写入/删除后不复用过期游标。完整范围的余额、筛选数量/净额、月度与每日统计独立于可见条数；相关表在同一事务中读取。关联 ID 每批最多 500 个，避免大可见集合或多物品关联触及 SQLite 参数上限。

## 可复现入口

`flutter test --no-pub benchmark/ledger_reads_benchmark.dart` 显式运行 1,000 / 10,000 / 100,000 条确定性流水，包含合成多币种、转账、借贷、归档、余额调整、物品与攒钱关系。输出 `.tooling/benchmarks/ledger-host.json`。每项暖机一次后测 10 次，报告 p50/p95、SELECT 数量、进程 RSS 和进程峰值。峰值是整个进程至该时刻的峰值，不是单个页面的独立峰值；批量插入计时不等于文件解析/账户映射的完整导入耗时。

旧全量基线在同一事务 SELECT 全部十张表；新方案包括 SQL 聚合、过滤、排序、分页及引用读取。旧基线没有额外计入旧页面的过滤/布局，属于保守比较。结果只证明该环境下的数据读取差异，不代表 Android 帧率或冷启动性能。

Android 使用实际命名目标运行：

```sh
flutter drive --profile --driver test_driver/ledger_profile.dart --target integration_test/ledger_profile_test.dart -d <android-device-id> --dart-define BENCHMARK_TARGET=<model-api-build>
```

报告另含首页/账户首次渲染时长与 build/raster 帧耗时。记录设备型号、OS/API、build、模式和原始报告；冷启动、整套导入交互和峰值内存的设备采样需要另行记录。当前没有连接设备，Android p95 < 300 ms/10,000 行的初始预算仍待测量后确认，不能用 Windows 数值宣称达标。

## 2026-10-27 Windows 结果

完整原始数据见 [ledger-host.json](evidence/v1.3.0/ledger-host.json)。以下均为暖缓存 p95，单位 ms：

| 流水数 | 旧全表读取 | 首页月份 | 切换月份 | 账户明细 |
| --- | --- | --- | --- | --- |
| 1,000 | 10.48 | 2.71 | 3.59 | 4.16 |
| 10,000 | 55.08 | 3.74 | 5.26 | 13.10 |
| 100,000 | 847.95 | 29.39 | 26.46 | 158.33 |

EXPLAIN 显示月份过滤使用既有 `entries_date`，账户连接使用主键；同日排序仍需临时 B-tree。当前主机结果不足以支持新增迁移/索引，故保留既有索引。账户全范围聚合仍随本账户记录增长，其他全量快照消费者尚未全部迁移；不声明无限规模支持。
