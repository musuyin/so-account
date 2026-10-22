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
4. 创建与 pubspec 一致的 `vX.Y.Z` tag 并推送。工作流构建固定签名通用包与 ARM64 / ARM32 / x86_64 专用包。分架构包使用 `-Pforce-version-code-ignoring-abi=true`，保持与 pubspec 一致的 build number，避免架构附加版本号影响以后升级。
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

## 差分与架构分发

清单保持 schema 1 和通用包顶层字段，旧客户端仍能下载完整包。新客户端按 Android 提供的 ABI 优先序选择 `variants`；分包安装的应用不使用单 APK 基线合成。首次升级到具备合成器的版本仍需下载整包，以后才能优先差分。

`tool/release_deltas.py` 无凭据读取公开 Release 列表，记录发现的版本数及所选基线，再读取最近两个公开正式版本的更新清单及精确 APK，校验基线摘要后生成补丁。使用同架构基线以及通用包基线；保留至少节省 20% 的补丁，每个补丁发布前反向还原，必须与待发布签名 APK 字节一致。GitHub Token 仅用于工作流发布，客户端不含凭据。

补丁算法 `soaccount-copy-v1` 是有界块复制/插入协议：88 字节 `SOADLT01` 头包含两个 uint64 小端文件长度及两个 SHA-256（旧包、新包）；后接 gzip 指令流。0 为 uint64 偏移 + uint32 长度的原包复制，1 为 uint32 长度 + 字节的插入，255 结束。复制块最多 4 MiB，插入最多 1 MiB；逐块读写，合成工作在独立 isolate 中进行。ZIP 成员数据边界用于寻找相同块，不解压重压 APK，不在手机重签名。完整的 APK 签名块、ZIP 元数据和资源均被字节保留。

客户端先匹配当前 APK 长度和 SHA-256，下载补丁后校验补丁大小/摘要，验证协议头、指令边界、输出长度和最终 SHA-256。合成成功才将临时文件改名供原生安装校验；基线不匹配或差分下载/合成失败会改用对应架构完整包。取消不会触发整包回退，临时补丁和未完成 APK 会清理。合成阶段取消将在工作返回后生效，不会安装结果。最终仍由原生入口核对递增版本、包名和原签名。

补丁大小取决于实际构建差异；依赖、引擎或大资源变化可能没有值得分发的补丁。全量包始终保留。该协议只优化 Android APK 下载，iOS 继续使用原有分发渠道。
