# GitHub Release 应用更新

更新源固定为公开仓库 `musuyin/so-account` 的最新正式 Release。自动检查每天最多一次，也可手动检查。只读取公开版本元数据，不上传账本，不在客户端内置 GitHub token；不自动消耗流量下载 APK。iOS 只展示版本与说明，APK 下载与安装仅在 Android 开启。

## 首次签名配置

正式 APK 必须一直使用同一个签名。调试构建继续使用开发签名，正式构建缺少签名时直接失败，禁止回退到临时调试密钥。

在项目根目录执行 `python tool/configure_signing.py`（需 JDK keytool，或设置 JAVA_HOME）。脚本仅首次生成 `android/signing/so-account-release.jks` 和 `android/key.properties`，已有任一文件时拒绝覆盖。两者都被 Git 忽略。请将两个文件备份到安全位置，密码也在 properties 中；丢失密钥后无法继续覆盖更新。

在 GitHub 仓库 Settings → Secrets and variables → Actions 中配置以下 repository secrets，值来自同一份本地签名：

| Secret | 值 |
| --- | --- |
| ANDROID_KEYSTORE_BASE64 | JKS/PKCS12 文件的完整 Base64，不带换行 |
| ANDROID_KEYSTORE_PASSWORD | storePassword |
| ANDROID_KEY_ALIAS | keyAlias |
| ANDROID_KEY_PASSWORD | keyPassword |

不得将签名密钥或密码提交到仓库。CI 从 secrets 临时恢复签名，发布结束清理。更换开发机器时应恢复原有签名，不要重新生成。

## 发布

1. 修改 `pubspec.yaml` 的版本名和 build number；build number 必须比所有历史正式版大。
2. 添加 `docs/releases/vX.Y.Z.md` 用户可读的更新说明。
3. 运行格式检查、静态检查、测试和 Android 构建；按阶段 commit 并 push main。
4. 创建与 pubspec 一致的 `vX.Y.Z` tag 并推送。`Publish Android release` 工作流验证、构建固定签名通用 APK，并生成更新清单与 SHA256SUMS。
5. 工作流先创建草稿并上传全部附件，成功后公开为 latest。检查 Release 的 APK、`so-account-update.json`、`SHA256SUMS.txt` 三个文件均存在。正式版本不要覆盖原附件。

若上传失败留下草稿，可删除该草稿后，从 Actions 手动运行工作流并指定已有 tag。已有公开版本禁止覆盖；修复应用需发更高版本。首次 v0.5.0 主要用于建立更新通道，安装该版本后才能从应用内接收后续版本。

## 更新清单 v1

```json
{
  "schema": 1,
  "package": "dev.soaccount.so_account",
  "version": "0.5.0",
  "build": 5,
  "apk": "SoAccount-v0.5.0-android.apk",
  "size": 123456,
  "sha256": "64位小写十六进制摘要"
}
```

只接受同仓库、同 tag、HTTPS GitHub Release 附件；重定向限制为 GitHub HTTPS CDN。清单与 Release 必须匹配，若 API 提供 digest 也必须一致。元数据限制 1 MB，APK 限制 250 MB。下载在应用私有缓存逐块写入临时文件，大小和 SHA-256 验证通过才改名为 APK；失败/取消清理临时文件。网络超时可重试，暂不提供断点续传或系统后台下载服务。退出更新页仍下载，进程被终止后需重新下载。

Android 原生安装入口只接受缓存 `app-updates/update.apk`，校验包名、递增版本、系统最低版本及当前签名，再通过仅授权该目录的 FileProvider 启动系统安装。Android 8+ 未授权时先打开本应用的“安装未知应用”设置，返回后再次点击安装。系统安装确认不能绕过，拒绝/取消后可重试，不会自动卸载、清空数据库。旧调试签名与正式签名不同的情况需按发布说明先备份后手动迁移。

## 验收

- 无 Release / 已是最新 / 有新版本 / GitHub 不可达或限流分别显示正确状态。
- 使用同一正式签名的低版本安装到 Android，保留账本和照片；发布更高 build，自动提示并在应用内下载覆盖，重开后数据存在。
- 安装权限拒绝/允许、系统安装取消、网络中断、取消下载、校验失败、错误签名、重开应用后重新下载。
- iOS 构建可通过，能检查版本与打开 Release 页面，不展示 APK 安装按钮。

自动测试覆盖清单验证、URL 限制、大小/摘要、取消清理重试和自动检查间隔。系统授权、真正的覆盖安装及跨版本数据保留必须以真机结果为准。
