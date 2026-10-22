package dev.soaccount.so_account

import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.soaccount/updates")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "info" -> {
                            val info = packageManager.getPackageInfo(packageName, 0)
                            result.success(mapOf(
                                "platform" to "android",
                                "version" to info.versionName,
                                "build" to versionCode(info),
                                "abis" to Build.SUPPORTED_ABIS.toList(),
                                "baseApk" to applicationInfo.sourceDir,
                                "splitApk" to !applicationInfo.splitSourceDirs.isNullOrEmpty()
                            ))
                        }
                        "install" -> result.success(installUpdate(
                            call.argument<String>("path") ?: error("安装包路径缺失"),
                            call.argument<Number>("build")?.toLong() ?: error("更新版本缺失")
                        ))
                        "openRelease" -> {
                            val uri = Uri.parse(call.argument<String>("url") ?: "")
                            require(uri.scheme == "https" && uri.host == "github.com" &&
                                (uri.path == "/musuyin/so-account/releases" ||
                                uri.path?.startsWith("/musuyin/so-account/releases/tag/v") == true)) {
                                "发布页面地址无效"
                            }
                            startActivity(Intent(Intent.ACTION_VIEW, uri))
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("UPDATE_ERROR", error.message ?: "无法打开系统安装界面", null)
                }
            }
    }

    @Suppress("DEPRECATION")
    private fun versionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()

    @Suppress("DEPRECATION")
    private fun signatures(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= 28) {
            info.signingInfo?.apkContentsSigners
        } else info.signatures
        return signatures?.map { it.toCharsString() }?.toSet() ?: emptySet()
    }

    @Suppress("DEPRECATION")
    private fun installUpdate(path: String, expectedBuild: Long): String {
        val file = File(path).canonicalFile
        val directory = File(cacheDir, "app-updates").canonicalFile
        require(file.parentFile == directory && file.name == "update.apk" && file.isFile) {
            "安装包不存在，请重新下载"
        }
        val flags = if (Build.VERSION.SDK_INT >= 28) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else PackageManager.GET_SIGNATURES
        val archive = packageManager.getPackageArchiveInfo(file.path, flags)
            ?: error("安装包无法识别，请重新下载")
        val installed = packageManager.getPackageInfo(packageName, flags)
        require(archive.packageName == packageName && versionCode(archive) == expectedBuild &&
            versionCode(archive) > versionCode(installed)) { "安装包应用标识或版本不匹配" }
        require((archive.applicationInfo?.minSdkVersion ?: Int.MAX_VALUE) <= Build.VERSION.SDK_INT) {
            "此版本不支持当前 Android 系统"
        }
        val currentSignatures = signatures(installed)
        require(currentSignatures.isNotEmpty() && currentSignatures == signatures(archive)) {
            "更新包签名与当前应用不同，无法覆盖安装。请先完整备份数据，再按发布说明迁移到正式版。"
        }
        if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
            startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName")))
            return "permission_required"
        }
        val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
        startActivity(Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
        return "installer_opened"
    }
}
