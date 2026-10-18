# SQLite 原生库下载

CI 在测试和构建前运行 `python3 tool/prepare_sqlite.py linux android`（Android）或 `python3 tool/prepare_sqlite.py ios`（iOS 模拟器）。本地遇到相同下载错误时也可在 `flutter pub get` 后运行。

脚本从已锁定的 sqlite3 包读取发布标签和 SHA-256，检查 HTTP 状态，对网络异常或哈希不匹配最多重试四次。只有验证通过的内容才会原子写入原生 hook 的共享下载缓存；sqlite3 hook 仍会再次验证。没有修改依赖包哈希，也没有禁用验证。

当前缓存路径适配 sqlite3 3.7.1。升级依赖时必须核对其 `assets.dart` 和 `compile/description.dart` 的缓存约定，并更新脚本的版本保护。不要通过替换预期哈希解决下载错误。

脚本测试：`python3 -m unittest discover -s tool -p 'test_*.py'`，覆盖损坏缓存、错误响应、重试成功及持续失败不写入缓存。
