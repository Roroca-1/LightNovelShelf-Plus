package app.lightnovel.shelf.plus

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings

import android.view.KeyEvent
import androidx.core.content.FileProvider
import androidx.core.view.WindowCompat
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
        preferHighestRefreshRate()
    }

    @Suppress("DEPRECATION")
    private fun preferHighestRefreshRate() {
        val current = windowManager.defaultDisplay.mode
        val best = windowManager.defaultDisplay.supportedModes
            .filter { it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight }
            .maxByOrNull { it.refreshRate }
            ?: return
        window.attributes = window.attributes.apply {
            preferredDisplayModeId = best.modeId
        }
    }

    private companion object {
        const val READER_VOLUME_KEY_CHANNEL = "app.lightnovel.shelf.plus/reader_volume_keys"
        const val APP_UPDATE_CHANNEL = "app.lightnovel.shelf/app_update"
        const val INSTALL_PERMISSION_REQUEST = 4021
    }

    private var readerVolumeKeyChannel: MethodChannel? = null
    private var readerVolumeKeyPagingEnabled = false
    private var appUpdateChannel: MethodChannel? = null
    private var pendingInstallPermission: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        readerVolumeKeyPagingEnabled = false
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            READER_VOLUME_KEY_CHANNEL,
        )
        channel.setMethodCallHandler { call, result ->
            if (call.method != "setEnabled") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            readerVolumeKeyPagingEnabled = call.arguments as? Boolean ?: false
            result.success(null)
        }
        readerVolumeKeyChannel = channel
        // 引擎可能接到新的 Activity 上，此时开关状态刚归零而 Dart 侧仍记着旧值，
        // 要它重发一次，否则阅读器里的音量键会一直不响应。
        channel.invokeMethod("resync", null)

        val updateChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APP_UPDATE_CHANNEL,
        )
        updateChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "supportedAbis" -> result.success(Build.SUPPORTED_ABIS.toList())
                "requestInstallPermission" -> requestInstallPermission(result)
                "install" -> {
                    val path = call.arguments as? String
                    if (path == null) {
                        result.error("bad_args", "缺少安装包路径", null)
                    } else {
                        installPackage(File(path))
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        appUpdateChannel = updateChannel
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        readerVolumeKeyChannel?.setMethodCallHandler(null)
        readerVolumeKeyChannel = null
        readerVolumeKeyPagingEnabled = false
        appUpdateChannel?.setMethodCallHandler(null)
        appUpdateChannel = null
        pendingInstallPermission?.success(false)
        pendingInstallPermission = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    // Android 8 以前是全局的「未知来源」开关，由系统安装器自己拦截提示。
    private fun canInstallPackages(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()

    private fun requestInstallPermission(result: MethodChannel.Result) {
        if (canInstallPackages()) {
            result.success(true)
            return
        }
        pendingInstallPermission?.success(false)
        pendingInstallPermission = result
        startActivityForResult(
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")),
            INSTALL_PERMISSION_REQUEST,
        )
    }

    // 设置页不回传授权结果，回到前台后重新查询一次。
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != INSTALL_PERMISSION_REQUEST) return
        pendingInstallPermission?.success(canInstallPackages())
        pendingInstallPermission = null
    }

    private fun installPackage(file: File) {
        val uri = FileProvider.getUriForFile(this, "$packageName.app_update", file)
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val channel = readerVolumeKeyChannel
        if (!readerVolumeKeyPagingEnabled || channel == null) {
            return super.dispatchKeyEvent(event)
        }
        val key = when (event.keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> "up"
            KeyEvent.KEYCODE_VOLUME_DOWN -> "down"
            else -> return super.dispatchKeyEvent(event)
        }
        // 音量键按住会自动重复上报 ACTION_DOWN，只认第一次，否则长按就一路翻到章末。
        // ACTION_UP 也要吞掉，只拦 ACTION_DOWN 的话音量不变但系统音量条会闪一下。
        if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
            channel.invokeMethod("onVolumeKey", key)
        }
        return true
    }
}
