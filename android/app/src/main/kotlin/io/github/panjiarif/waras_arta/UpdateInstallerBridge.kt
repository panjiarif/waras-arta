package io.github.panjiarif.waras_arta

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

/** Only installs verified self-updates from the app's dedicated private cache. */
class UpdateInstallerBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "io.github.panjiarif.waras_arta/app_updates")
    private val executor = Executors.newSingleThreadExecutor()
    private var pendingPermission: MethodChannel.Result? = null
    private var pendingInstall: MethodChannel.Result? = null
    @Volatile private var closed = false

    init { channel.setMethodCallHandler(::handle) }

    private fun canInstall(): Boolean = Build.VERSION.SDK_INT < 26 || activity.packageManager.canRequestPackageInstalls()

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "canInstall" -> result.success(canInstall())
            "requestInstallPermission" -> requestPermission(result)
            "installUpdate" -> install(call, result)
            else -> result.notImplemented()
        }
    }

    @Suppress("DEPRECATION")
    private fun requestPermission(result: MethodChannel.Result) {
        if (pendingPermission != null || pendingInstall != null) {
            result.error("busy", null, null)
            return
        }
        if (canInstall()) { result.success(true); return }
        pendingPermission = result
        try {
            activity.startActivityForResult(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}")), PERMISSION_REQUEST)
        } catch (_: Exception) {
            pendingPermission = null
            result.error("permission_denied", null, null)
        }
    }

    fun onActivityResult(requestCode: Int) {
        if (requestCode != PERMISSION_REQUEST) return
        val result = pendingPermission ?: return
        pendingPermission = null
        result.success(canInstall())
    }

    private class Rejected(val code: String) : Exception()

    private fun install(call: MethodCall, result: MethodChannel.Result) {
        if (pendingInstall != null || pendingPermission != null) { result.error("busy", null, null); return }
        if (!canInstall()) { result.error("permission_denied", null, null); return }
        val path = call.argument<String>("path")
        val sha256 = call.argument<String>("sha256")
        val size = call.argument<Number>("size")?.toLong()
        val version = call.argument<String>("version")
        if (path == null || sha256 == null || !sha256.matches(Regex("[a-f0-9]{64}")) || size == null || size !in 1..MAX_APK_BYTES || version.isNullOrBlank() || version.length > 100) {
            result.error("invalid_apk", null, null)
            return
        }
        pendingInstall = result
        executor.execute {
            try {
                val directory = File(activity.cacheDir, "updates").canonicalFile
                val file = File(path).canonicalFile
                if (file.parentFile != directory || !file.name.matches(Regex("update-[0-9]+\\.apk"))) throw Rejected("invalid_apk")
                if (!file.isFile) throw Rejected("file_missing")
                if (file.length() != size) throw Rejected("invalid_apk")
                val digest = MessageDigest.getInstance("SHA-256")
                file.inputStream().use { input ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        if (Thread.currentThread().isInterrupted) throw Rejected("activity_unavailable")
                        val count = input.read(buffer)
                        if (count < 0) break
                        digest.update(buffer, 0, count)
                    }
                }
                val actual = digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
                if (actual != sha256) throw Rejected("invalid_apk")
                verifyArchive(file, version)
                activity.runOnUiThread {
                    if (closed || pendingInstall !== result) return@runOnUiThread
                    try {
                        if (!canInstall()) throw Rejected("permission_denied")
                        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.update_files", file)
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            clipData = ClipData.newRawUri("Pembaruan Waras Arta", uri)
                        }
                        activity.startActivity(intent)
                        pendingInstall = null
                        result.success(true) // Installer opened, not installation success.
                    } catch (error: Exception) {
                        finishError(result, (error as? Rejected)?.code ?: "installer_unavailable")
                    }
                }
            } catch (error: Exception) {
                activity.runOnUiThread {
                    if (!closed) finishError(result, (error as? Rejected)?.code ?: "invalid_apk")
                }
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun verifyArchive(file: File, version: String) {
        val pm = activity.packageManager
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
        val archive = pm.getPackageArchiveInfo(file.path, flags) ?: throw Rejected("invalid_apk")
        val installed = pm.getPackageInfo(activity.packageName, flags)
        if (archive.packageName != activity.packageName || archive.versionName != version || (archive.applicationInfo?.minSdkVersion ?: Int.MAX_VALUE) > Build.VERSION.SDK_INT) throw Rejected("invalid_apk")
        val newCode = if (Build.VERSION.SDK_INT >= 28) archive.longVersionCode else archive.versionCode.toLong()
        val oldCode = if (Build.VERSION.SDK_INT >= 28) installed.longVersionCode else installed.versionCode.toLong()
        if (newCode <= oldCode) throw Rejected("not_newer")
        fun signers(info: PackageInfo): Set<String> {
            val signatures = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
            return signatures?.map { signature -> MessageDigest.getInstance("SHA-256").digest(signature.toByteArray()).joinToString("") { "%02x".format(it.toInt() and 0xff) } }?.toSet() ?: emptySet()
        }
        val expected = signers(installed)
        if (expected.isEmpty() || expected != signers(archive)) throw Rejected("invalid_apk")
    }

    private fun finishError(result: MethodChannel.Result, code: String) {
        if (pendingInstall !== result) return
        pendingInstall = null
        result.error(code, null, null)
    }

    fun close() {
        closed = true
        channel.setMethodCallHandler(null)
        pendingPermission?.error("activity_unavailable", null, null)
        pendingPermission = null
        pendingInstall?.error("activity_unavailable", null, null)
        pendingInstall = null
        executor.shutdownNow()
    }

    companion object {
        private const val PERMISSION_REQUEST = 0x5743
        private const val MAX_APK_BYTES = 256L * 1024 * 1024
    }
}
