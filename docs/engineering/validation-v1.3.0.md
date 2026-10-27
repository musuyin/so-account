# v1.3.0 验证记录

日期：2026-10-27。目标：v1.3.0 / 1.3.0+18，Schema 9。整改依据：[2026-10-27 评审计划](project-review-coding-plan-2026-10-27.md)。

| 评审项 | 实施结果 | 验证与边界 |
| --- | --- | --- |
| R1 备份限制 | 导出/恢复共用行数、文件数、展开/压缩/清单容量；提前 COUNT，清单计入体积 | 小限额边界测试、完整合成账本异库恢复、旧格式、损坏与回滚；不截断记录 |
| R2 恢复覆盖 | 独立 debug 包、完整合成 fixture、宿主强杀/重启/提交前中断，手动 CI job | [设备步骤](device-acceptance.md)；Windows 无连接设备，模拟器与真机结果分别记录 |
| R3 查询范围 | 根组件仅订阅偏好；首页/明细 SQL 范围、完整聚合及稳定分页，同事务引用 | 一致性/归档/币种/筛选/页间删除测试；[主机测量](ledger-performance.md)，Android profile 待设备 |
| R4 状态抽取 | EntryDraft 的方向转换与保存；ImportWorkflow 的映射/预览/提交/重试状态 | 现有表单/导入流程、草稿取消、归档保存失败、导入失败重试及防重复提交 |
| R5 渲染证据 | 四配色浅深、320/390、大字矩阵；CI 保留截图与日志 | [检查表](ui-acceptance.md)；系统键盘/触感/文件面板仍需真机 |
| R6 文档 | Schema 9、完整模块树、Ledger/Inventory 购买事务边界 | 本文区分本地、CI、公开发布和设备证据；历史发布记录保留原日期/测试数 |

## 验证结果

Windows 本地：固定 Flutter 3.47.7 / Dart 3.13.5；静态分析无问题、格式检查、272 项 Flutter 回归、17 项 Python 工具测试通过。备份容量覆盖行数、文件数、清单/压缩/展开体积的下界/等值/上界；完整合成账本恢复到新数据库，并验证全表/余额/照片与提交失败回滚。SQL 大关联集验证 1201 个物品引用跨批次读取不遗漏。

渲染：已检查 96 张新增矩阵图片（账户类型、资产、月历、六周月历、记账键盘、记物弹窗，各 16 张），逐组查看六张联系表，并原尺寸复查 320 像素的浅色记物弹窗和深色月历。直接选择、对比度、日历标记和保存栏可读；窄屏弹窗内容可滚动。保留既有金额/语义隐私、取消/保存和日期筛选测试，不把截图视为系统键盘或真机操作验收。

隔离 debug 恢复 APK 构建成功，并经 aapt 确认包名为 `dev.soaccount.so_account.recovery`。最终正式构建：通用、arm64-v8a、armeabi-v7a、x86_64 APK 全部成功；aapt 确认 `dev.soaccount.so_account` / 1.3.0 / build 18，apksigner 确认四包与 v1.2.0 公开 ARM64 包的固定证书一致。本地通用 APK SHA-256：`f4ec14b6af166a9030cec8f57e470fde23dbdb7a6254c3e761d0d697252b475e`。本地构建摘要不要求与不同构建环境的公开包相同，公开包另外验证。

CI：[Mobile checks 40510726799](https://github.com/musuyin/so-account/actions/runs/40510726799) 在源码 `2e13834241cc258c973601677a10c7191e0dc0f6` 全部成功：Linux Android 格式/静态分析/完整测试/数据库生成一致性/构建，以及 macOS iOS 模拟器构建。首次 push 自动运行被同 SHA 的手动工作流替代，取消状态不作为验收结果。

恢复证据：Android 15 / API 35 / x86_64 模拟器、候选 1.3.0 (18)、Schema 9、fixture synthetic-v1，seed、强杀重启、恢复失败及重启、提交前强杀/回滚后重启、成功恢复及重启全部通过。恢复提交前的 `ready-to-kill` 是宿主强杀检查点，随后独立 verify-failure 已通过。[归档结果与设备信息](evidence/v1.3.0/android-recovery.json) 源自 CI artifact `android-device-recovery` (12737012396)；截图 artifact `android-ui-evidence` (12736658861) 也已上传。

公开发布：[Release workflow 40512347908](https://github.com/musuyin/so-account/actions/runs/40512347908) 成功，[v1.3.0](https://github.com/musuyin/so-account/releases/tag/v1.3.0) 为公开 latest 正式版，共 20 个资产。v1.3.0 标签指向上述已验收源码提交；随后补记的验证文档不改变应用代码。

公开安装包与更新：核对通用及三种 ABI 的清单、大小和 SHA-256 清单/GitHub 摘要；实际下载 ARM64 APK 检查包名、版本 1.3.0/build 18、固定证书和摘要。公开 ARM64 SHA-256：`3ac67e13253e57e2ba4d0cb6e6860efe8d7f86a1c767675fd887452db9036a44`。使用公开 v1.2.0 ARM64 包应用公开差分，重建包与 v1.3.0 逐字节摘要一致。真实 AppUpdateService 另外验证三个 ABI/通用元数据并实际走差分下载；build 17 能发现 18，build 18 返回已是最新版本。结果与证书见 [公开验证数据](evidence/v1.3.0/public-release.json)。Release CI 另外保留 `release-ui-evidence` (12737108447) 与构建日志。

Android 真机覆盖安装、跨版本数据保留、文件提供器、权限/低存储/iPhone 操作验收仍待执行。Android profile 冷启动、帧时、真实导入耗时与设备峰值内存尚未测量；主机测量不替代这些结果。
