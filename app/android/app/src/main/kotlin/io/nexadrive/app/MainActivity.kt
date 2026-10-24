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

    /// Serializes APK staging off the platform thread so a large installer
    /// never blocks the UI while the session is written.
    private val installerExecutor: Executor = Executors.newSingleThreadExecutor()

    /// Listing a tree is metadata-only and runs off the platform thread so a
    /// huge folder never blocks the UI.
    private val folderExecutor: Executor = Executors.newSingleThreadExecutor()

    /// Content-provider reads run in parallel: one upload chunk per worker.
    /// A range is read into memory only for the duration of that chunk; the
    /// folder is never copied into app storage.
    private val sourceExecutor: Executor = Executors.newFixedThreadPool(4)

    /// The pending result of an open tree picker.
    private var pendingFolderResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, UPDATER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "currentAbi" -> result.success(Build.SUPPORTED_ABIS.firstOrNull())
                "installApk" -> installApk(call.argument<String>("path"), result)
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

        MethodChannel(messenger, FOLDER_PICKER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickFolder" -> pickFolder(result)
                "listFolder" -> listFolder(
                    call.argument<String>("uri"),
                    result,
                )
                "readSourceRange" -> readSourceRange(
                    call.argument<String>("uri"),
                    (call.argument<Number>("offset"))?.toLong(),
                    call.argument<Number>("length")?.toInt(),
                    result,
                )
                else -> result.notImplemented()
            }
        }
    }

    // -------------------------------------------------------- folder picker

    /**
     * Opens the system tree picker.
     *
     * The user grants access to exactly one tree; the grant is what makes the
     * tree readable, so no storage permission is involved.
     */
    private fun pickFolder(result: MethodChannel.Result) {
        if (pendingFolderResult != null) {
            result.error("busy", "A folder picker is already open", null)
            return
        }
        pendingFolderResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
        }
        try {
            startActivityForResult(intent, FolderPickerBridge.REQUEST_CODE)
        } catch (e: android.content.ActivityNotFoundException) {
            pendingFolderResult = null
            result.error("unavailable", "No folder picker is available", null)
        }
    }

    /**
     * Lists the picked tree without copying it.
     *
     * Each file carries its document URI, so the upload queue can stream the
     * bytes later, directly from the provider.
     */
    private fun listFolder(uri: String?, result: MethodChannel.Result) {
        if (uri.isNullOrEmpty()) {
            result.error("invalid", "No folder was picked", null)
            return
        }
        val treeUri = android.net.Uri.parse(uri)
        folderExecutor.execute {
            try {
                val bridge = FolderPickerBridge(this)
                val files = bridge.readTree(treeUri).map { entry ->
                    mapOf(
                        "path" to entry.relativePath,
                        "name" to entry.name,
                        "size" to entry.size,
                        "sourceUri" to entry.uri,
                    )
                }
                val payload = mapOf(
                    "name" to bridge.displayName(treeUri),
                    "files" to files,
                )
                runOnUiThread { result.success(payload) }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("failed", e.message ?: "The folder could not be read", null)
                }
            }
        }
    }

    /**
     * Reads one upload chunk (at most 32 MiB) from a document URI.
     *
     * The provider stream is opened per request and skipped/seeded to
     * [offset], so a resumed upload does not re-read the earlier bytes. No
     * part of the tree is written to the app cache.
     */
    private fun readSourceRange(
        uri: String?,
        offset: Long?,
        length: Int?,
        result: MethodChannel.Result,
    ) {
        if (uri.isNullOrEmpty() || offset == null || offset < 0 ||
            length == null || length < 0 || length > 32 * 1024 * 1024
        ) {
            result.error("invalid", "Invalid content range", null)
            return
        }
        sourceExecutor.execute {
            try {
                val descriptor = contentResolver.openFileDescriptor(
                    android.net.Uri.parse(uri),
                    "r",
                ) ?: throw IllegalStateException("The document is no longer available")
                val bytes = descriptor.use { pfd ->
                    FileInputStream(pfd.fileDescriptor).use { input ->
                        var seekable = true
                        try {
                            input.channel.position(offset)
                        } catch (_: Exception) {
                            seekable = false
                        }
                        if (!seekable) skipFully(input, offset)
                        readExactly(input, length)
                    }
                }
                runOnUiThread { result.success(bytes) }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("read_failed", e.message ?: "The document could not be read", null)
                }
            }
        }
    }

    private fun skipFully(input: FileInputStream, offset: Long) {
        var remaining = offset
        val buffer = ByteArray(64 * 1024)
        while (remaining > 0) {
            val wanted = if (remaining > buffer.size) buffer.size else remaining.toInt()
            val read = input.read(buffer, 0, wanted)
            if (read < 0) throw java.io.EOFException("The document ended before the resume offset")
            remaining -= read
        }
    }

    private fun readExactly(input: FileInputStream, length: Int): ByteArray {
        val buffer = ByteArray(length)
        var total = 0
        while (total < length) {
            val read = input.read(buffer, total, length - total)
            if (read < 0) break
            total += read
        }
        return if (total == length) buffer else buffer.copyOf(total)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != FolderPickerBridge.REQUEST_CODE) return
        val result = pendingFolderResult ?: return
        pendingFolderResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        // Keep read access across restarts so a queued folder upload can still
        // stream from the tree after the app is killed and reopened.
        try {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        } catch (_: SecurityException) {
            // Some providers do not offer a persistable grant; the tree is
            // still readable for this session.
        }
        result.success(uri.toString())
    }

    // ------------------------------------------------------------- updater

    /// Streams the verified APK into a PackageInstaller session and commits
    /// it. Returns true only when the system installer accepted the commit and
    /// the session is staged. The user still confirms in the system dialog;
    /// no root, no silent install.
    ///
    /// The stream/commit runs on a background executor because an APK is tens
    /// of megabytes and doing that I/O on the platform thread freezes the UI
    /// (and can trip an ANR) while the dialog is being scheduled.
    private fun installApk(path: String?, result: MethodChannel.Result) {
        val file = path?.let { File(it) }
        if (file == null || !file.exists() || !file.isFile || file.length() == 0L) {
            result.success(false)
            return
        }
        installerExecutor.execute {
            val launched = stageAndCommit(file)
            runOnUiThread { result.success(launched) }
        }
    }

    private fun stageAndCommit(file: File): Boolean {
        val packageInstaller = packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(
            PackageInstaller.SessionParams.MODE_FULL_INSTALL,
        )
        params.setAppPackageName(packageName)
        val sessionId: Int
        try {
            sessionId = packageInstaller.createSession(params)
        } catch (_: SecurityException) {
            // The installer service refused the session outright.
            return false
        } catch (_: IllegalStateException) {
            return false
        }

        // The status receiver must be an explicit component so it survives
        // Android 14's implicit-broadcast restrictions; see
        // InstallResultReceiver, which launches the confirmation dialog.
        val statusIntent = Intent(this, InstallResultReceiver::class.java)
            .setAction(ACTION_INSTALL_STATUS)
        val statusReceiver = PendingIntent.getBroadcast(
            this,
            sessionId,
            statusIntent,
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
        } finally {
            try {
                session.close()
            } catch (_: Exception) {
            }
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

    private var authExecutor: Executor? = null

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
        authExecutor = executor
        val prompt = BiometricPrompt(
            activity,
            executor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(
                    authenticationResult: BiometricPrompt.AuthenticationResult,
                ) {
                    try {
                        (executor as? java.util.concurrent.ExecutorService)?.shutdown()
                    } catch (_: Exception) {
                    }
                    authExecutor = null
                    result.success(true)
                }

                override fun onAuthenticationError(
                    errorCode: Int,
                    errString: CharSequence,
                ) {
                    try {
                        (executor as? java.util.concurrent.ExecutorService)?.shutdown()
                    } catch (_: Exception) {
                    }
                    authExecutor = null
                    if (errorCode == BiometricPrompt.ERROR_NEGATIVE_BUTTON ||
                        errorCode == BiometricPrompt.ERROR_USER_CANCELED
                    ) {
                        result.success(false)
                    } else {
                        result.error("auth_error", errString.toString(), null)
                    }
                }

                override fun onAuthenticationFailed() {
                    // Do not shut down here; user may retry
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
        private const val FOLDER_PICKER_CHANNEL = "nexadrive/folder_picker"
        const val ACTION_INSTALL_STATUS = "io.nexadrive.app.INSTALL_STATUS"
    }
}
