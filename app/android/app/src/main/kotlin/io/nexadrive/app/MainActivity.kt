package io.nexadrive.app

import android.app.Activity
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.IntentSender
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.FileProvider
import androidx.fragment.app.FragmentActivity
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.util.concurrent.Executor
import java.util.concurrent.Executors

/// Host-side bridge for two platform features.
///
/// **Updater** (`nexadrive/updater`): the Flutter side downloads a verified
/// APK, then hands the absolute file path here. Android never installs
/// silently: the APK is streamed into a [PackageInstaller] session, the
/// system confirmation dialog runs, and any blocked "unknown apps" state is
/// surfaced so the user can fix it in settings. Progress is reported back to
/// Flutter while the session is staged.
///
/// **App Lock** (`nexadrive/app_lock`): the device's own screen-lock
/// credential, asked for through [BiometricPrompt] — BiometricManager
/// authenticates against whatever the device has (fingerprint, face, or the
/// PIN/pattern/password fallback) and never stores or invents a NexaDrive
/// password.
///
/// The activity extends [FlutterFragmentActivity] because androidx
/// [BiometricPrompt] requires a FragmentActivity host.
class MainActivity : FlutterFragmentActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, UPDATER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "currentAbi" -> result.success(Build.SUPPORTED_ABIS.firstOrNull())
                "installApk" -> result.success(installApk(call.argument<String>("path")))
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

        MethodChannel(messenger, APP_LOCK_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "canAuthenticate" -> result.success(canAuthenticate())
                "authenticate" -> {
                    val reason = call.argument<String>("reason") ?: "Unlock NexaDrive"
                    authenticate(result, reason)
                }
                else -> result.notImplemented()
            }
        }
    }

    // ------------------------------------------------------------- updater

    /// Streams the verified APK into a PackageInstaller session and commits
    /// it. Returns true only when the system installer actually took over
    /// (or staged the session and asked the user to confirm). The user always
    /// confirms; no root, no silent install.
    ///
    /// For a sideloaded (non-Play) app the session flow surfaces Android's
    /// "install unknown apps" consent as a system dialog; when the device
    /// answers that dialog with a refusal the ActivityResult comes back as
    /// RESULT_CANCELED, which Flutter maps to its needsUserAction state.
    private fun installApk(path: String?): Boolean {
        val file = path?.let { File(it) } ?: return false
        if (!file.exists() || !file.isFile || file.length() == 0L) return false

        val packageInstaller = packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(
            PackageInstaller.SessionParams.MODE_FULL_INSTALL,
        )
        val sessionId: Int
        try {
            sessionId = packageInstaller.createSession(params)
        } catch (_: SecurityException) {
            // The installer service refused the session outright.
            return false
        } catch (_: IllegalStateException) {
            return false
        }

        val statusReceiver = PendingIntent.getBroadcast(
            this,
            sessionId,
            Intent(ACTION_INSTALL_STATUS).setPackage(packageName),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            },
        )

        val session: PackageInstaller.Session
        try {
            session = packageInstaller.openSession(sessionId)
        } catch (_: Exception) {
            try {
                packageInstaller.abandonSession(sessionId)
            } catch (_: Exception) {
            }
            return false
        }

        try {
            // openWrite's lengthBytes gives the installer a real size hint for
            // its progress UI. The SHA-256 was already verified client-side
            // before this handoff, so the session needs no extra metadata.
            FileInputStream(file).use { input ->
                session.openWrite("nexadrive", 0, file.length()).use { out ->
                    input.copyTo(out, 64 * 1024)
                    session.fsync(out)
                }
            }
            session.commit(statusReceiver.intentSender)
            return true
        } catch (_: SecurityException) {
            // Missing REQUEST_INSTALL_PACKAGES or user-consent enforcement.
            try {
                session.abandon()
            } catch (_: Exception) {
            }
            return false
        } catch (_: Exception) {
            try {
                session.abandon()
            } catch (_: Exception) {
            }
            return false
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
        } catch (_: android.content.ActivityNotFoundException) {
            // The OEM has no such screen; the install dialog will surface the
            // blocking reason itself.
        }
    }

    private fun openAppSettings() {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            .setData(Uri.parse("package:$packageName"))
        try {
            startActivity(intent)
        } catch (_: android.content.ActivityNotFoundException) {
            // No detail screen available; nothing else to do.
        }
    }

    // ------------------------------------------------------------- app lock

    /// Whether the device currently has a screen lock that can be asked for.
    /// BIOMETRIC_ERROR_NONE_ENROLLED means the device has no secure lock at
    /// all, so App Lock cannot be honored and the setting must not pretend
    /// otherwise.
    private fun canAuthenticate(): Boolean {
        val manager = BiometricManager.from(this)
        val authenticators = BiometricManager.Authenticators.DEVICE_CREDENTIAL or
            BiometricManager.Authenticators.BIOMETRIC_WEAK
        return when (manager.canAuthenticate(authenticators)) {
            BiometricManager.BIOMETRIC_SUCCESS -> true
            else -> false
        }
    }

    private fun authenticate(result: MethodChannel.Result, reason: String) {
        val activity: Activity = this
        if (activity !is FragmentActivity) {
            result.error("unavailable", "No fragment activity host", null)
            return
        }
        val authenticators = BiometricManager.Authenticators.DEVICE_CREDENTIAL or
            BiometricManager.Authenticators.BIOMETRIC_WEAK
        if (!canAuthenticate()) {
            result.error(
                "no_device_credential",
                "This device has no screen lock configured",
                null,
            )
            return
        }

        val executor: Executor = Executors.newSingleThreadExecutor()
        val prompt = BiometricPrompt(
            activity,
            executor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(
                    authenticationResult: BiometricPrompt.AuthenticationResult,
                ) {
                    result.success(true)
                }

                override fun onAuthenticationError(
                    errorCode: Int,
                    errString: CharSequence,
                ) {
                    if (errorCode == BiometricPrompt.ERROR_NEGATIVE_BUTTON ||
                        errorCode == BiometricPrompt.ERROR_USER_CANCELED
                    ) {
                        result.success(false)
                    } else {
                        result.error("auth_error", errString.toString(), null)
                    }
                }
            },
        )

        val promptInfo = BiometricPrompt.PromptInfo.Builder()
            .setTitle(getString(R.string.app_lock_prompt_title))
            .setSubtitle(getString(R.string.app_lock_prompt_subtitle))
            .setDescription(reason)
            // Allowed combination on API 30+: BiometricPrompt shows its own
            // device-credential button that opens the system PIN/pattern flow.
            .setAllowedAuthenticators(authenticators)
            .setConfirmationRequired(false)
            .build()

        runOnUiThread { prompt.authenticate(promptInfo) }
    }

    companion object {
        private const val UPDATER_CHANNEL = "nexadrive/updater"
        private const val APP_LOCK_CHANNEL = "nexadrive/app_lock"
        private const val ACTION_INSTALL_STATUS = "io.nexadrive.app.INSTALL_STATUS"
    }
}
