# v2.2.3 验证记录

日期：2026-11-12。版本：2.2.3+32，Schema 11。

## 范围

- 心愿和攒钱统一为目标，不再选择或筛选类型；名称、目标金额、初始已攒金额、存入、取出及手动标记已实现共用同一套行为。
- 旧数据的类型字段继续保存以兼容备份和 CSV，不迁移或删除旧记录。旧攒钱目标也允许手动标记已实现，无需先达到目标金额；此操作不生成购买流水。
- 目标表单币种、优先级使用平铺芯片，有进度记录时继续锁定币种。
- 记账金额包含运算符时，键盘右下角由保存切换为等号；计算成功后恢复保存，计算本身不写入流水。移除输入框内的等号。

## 本地验证

- 格式检查、静态分析及 17 项 Python 工具测试通过。
- 完整 Flutter 回归：401 项通过，Windows 跳过 1 项既有符号链接用例。包含日期筛选、金额隐私和原有账户/借贷/备份回归。
- 正式签名通用 APK 构建通过，已核对包名 `dev.soaccount.so_account`、版本 `2.2.3+32`，证书 SHA-256 与 v2.1.3 一致（`f0db22ad213879a06fcc7e55a40dd80fa230725ab52f230e77c5d55fd1469634`）。
- 新增测试覆盖统一目标名称与金额、初始进度、优先级直接选择、旧攒钱目标、编辑币种锁定、取消修改、标记已实现；金额测试覆盖运算优先级、外部修改同步、退格/长按清空、不完整算式、除零及负数结果。
- 已目检 320 像素、1.4 倍文字的浅深主题截图：[目标表单浅色](evidence/v2.2.3/unified-goal-form-light.png)、[深色](evidence/v2.2.3/unified-goal-form-dark.png)，[计算浅色](evidence/v2.2.3/amount-equals-light.png)、[深色](evidence/v2.2.3/amount-equals-dark.png)，[保存浅色](evidence/v2.2.3/amount-save-light.png)、[深色](evidence/v2.2.3/amount-save-dark.png)。截图使用合成数据。
- 本次未进行 Android 真机覆盖安装与跨版本数据保留验收。

## 发布验证

- 发布源码：`5a9392cfd039999fe142ec0836c73e4146ba2fd0`，标签 `v2.2.3`。
- [发布工作流](https://github.com/musuyin/so-account/actions/runs/43128892315)和 [Mobile checks](https://github.com/musuyin/so-account/actions/runs/43128833082)成功；Android 与 iOS 模拟器构建、数据库生成一致性通过。两条 Linux 测试作业均为 402 项通过，另有 17 项 Python 工具测试及静态分析通过。
- 正式签名通用及三架构 APK、签名校验、v2.1.3/v2.1.2 增量生成与逐个还原检查通过。
- [公开 Release](https://github.com/musuyin/so-account/releases/tag/v2.2.3)确认为 latest，20 个附件完整；更新清单、校验和、APK 和补丁的公开元数据大小、摘要一致。
- 已下载公开 ARM64 APK，核对版本 `2.2.3+32`、包名和固定签名，并以公开 v2.1.3 ARM64 基线及公开补丁精确还原新版 APK。见 [结构化核验结果](evidence/v2.2.3/public-verification.json)。
