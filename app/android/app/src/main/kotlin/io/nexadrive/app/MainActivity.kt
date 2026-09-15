package io.nexadrive.app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Updater bridge for the Flutter Update Center.
///
/// The Flutter side downloads a verified artifact, then hands the absolute
/// file path back here. Android never installs silently: the system package
/// installer receives a [FileProvider] content URI (never a raw path), the
/// user confirms in the stock install dialog, and any blocked "unknown apps"
/// state is surfaced so the user can fix it in settings.
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "currentAbi" -> result.success(Build.SUPPORTED_ABIS.firstOrNull())
                    "installApk" -> result.success(
                        installApk(call.argument<String>("path")),
                    )
                    "openUnknownSourceSettings" -> {
                        openUnknownSourceSettings()
                        result.success(null)
                    }
                    "openAppSettings" -> {
                        openAppSettings()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// Hands the downloaded APK to the system installer. Returns true only when
    /// an activity was actually launched. The user always confirms; no root.
    private fun installApk(path: String?): Boolean {
        val file = path?.let { java.io.File(it) } ?: return false
        if (!file.exists() || !file.isFile) return false
        val uri: Uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            file,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }

    private fun openUnknownSourceSettings() {
        // API 26+: the per-source "install unknown apps" consent screen.
        // Older devices: fall back to the app details page (the toggle lives
        // under Settings -> Security there).
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
        }
        intent.data = Uri.parse("package:$packageName")
        try {
            startActivity(intent)
        } catch (_: ActivityNotFoundException) {
            // The OEM has no such screen; the install dialog will surface the
            // blocking reason itself.
        }
    }

    private fun openAppSettings() {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            .setData(Uri.parse("package:$packageName"))
        try {
            startActivity(intent)
        } catch (_: ActivityNotFoundException) {
            // No detail screen available; nothing else to do.
        }
    }

    companion object {
        private const val CHANNEL = "nexadrive/updater"
    }
}