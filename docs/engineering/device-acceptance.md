# 设备恢复与升级验收

所有自动化使用合成数据。不得清除个人账本或在个人安装上运行清库命令。结果按 Windows、本地模拟器、CI Android 模拟器、Android 真机、iOS 模拟器和 iPhone 分开记录。

## Android 进程恢复

保留 `integration_test/persistence_test.dart` 的数据库关闭重开测试。它不代表进程强杀覆盖。

独立 debug 包 `dev.soaccount.so_account.recovery` 使用私有 `recovery-fixture/ledger.sqlite`，入口 `integration_test/recovery_app.dart`。Gradle 只在 `-PrecoveryHarness=true` 时切换包名，并拒绝此配置的 release 构建。宿主驱动先用 aapt 检查包名；若该测试包已安装则拒绝，要求使用干净模拟器，绝不自动 clear/uninstall。

```sh
flutter build apk --debug --target integration_test/recovery_app.dart -PrecoveryHarness=true
python tool/device_recovery.py --apk build/app/outputs/flutter-apk/app-debug.apk --aapt <sdk-build-tools/aapt> --serial <emulator-id>
```

合成样例包含 CNY/USD、同币种转账、借入/部分偿还、归档账户、独立余额调整、物品/真实 PNG/购买关联、攒钱进度和外观偏好。每次比较全部表的稳定排序行、原始 ID、审计时间和所有账户余额；照片路径允许恢复重映射，但比较实际字节并拒绝缺失照片。

fixture 的预期余额（最小单位）为：CNY 钱包 118800、已归档银行卡 105000、USD 账户 99800、CNY 应付款 15000；攒钱进度 1234。各币种分别核对，不加总换算。seed 将完整实际快照作为持久化基线，后续 verify 比较全部表、全部账户余额及照片字节；CI 的 passed 表示与该基线一致，不代表真人账本或真实覆盖安装通过。

| 场景 | 宿主操作 | 预期 |
| --- | --- | --- |
| seed → force-stop → verify | seed 成功后杀死整个进程并重新启动 | 所有行、余额、关联和图片与持久化基线一致 |
| restore-failure → force-stop → verify-failure | 在新图片发布、行替换后、提交前抛错，再杀进程重开 | 原始账本完整、图片可用 |
| restore-crash → force-stop → verify-failure | app 在提交前写入 ready-to-kill 后阻塞；宿主真正 force-stop | SQLite 回滚、原数据完整；允许无引用新图片待延迟清理 |
| restore-success → force-stop → verify | 完成恢复后杀进程并重开 | 恢复后完整表、余额和照片仍一致 |

手动触发 Mobile checks，勾选 `device_recovery`。CI 发布 `android-device-recovery/results.json`、OS/API/设备属性和 logcat；常规 CI 暂不启用，待可靠性建立后提升。每次运行记录代码 SHA、版本/build、设备/OS/API、fixture、预期与实际、运行链接及证据。模拟器通过不能代表真机升级或文件提供器验收。

## Android 真机操作

使用专门的测试设备或显式创建的合成测试账本。先将备份另存到应用外，再确认候选包与前版使用同一正式签名。固定前版 v1.2.0 (17) → 候选 v1.3.0 (18)，不卸载、不清数据，以 `adb install -r <candidate.apk>` 或系统安装器覆盖安装。核对包名/版本/build/证书、全部币种余额、借贷原始 ID/剩余本金、归档状态、购买关联、照片及攒钱记录，强杀重开后再核对。记录安装器实际结果；签名/摘要检查不等于安装通过。

逐项操作 Android DocumentsUI 的本机/下载/可用云盘保存和打开完整备份，测试取消保存、取消分享、拒绝相机/相册权限、选择期间系统回收后恢复 lost selection，以及低存储下导出、拍照和恢复失败。失败时不得出现部分提交或丢失旧图片。保留设备日志、截图、预期/实际与成功或失败原因。

iOS 模拟器构建、iPhone 文件提供器/相机/分享、跨平台恢复单列记录。当前真机与 iPhone 结果见 [版本验证记录](validation-v1.3.0.md)，未执行项保持待验收。
