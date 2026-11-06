package io.nexadrive.app

import android.app.Activity
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.IntentSender
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import android.provider.MediaStore
import android.provider.Settings
import org.json.JSONArray
import org.json.JSONObject
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.fragment.app.FragmentActivity
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.util.concurrent.Executor
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
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

    /** Open provider streams stay alive across sequential chunk reads. */
    private data class SourceSession(
        val descriptor: ParcelFileDescriptor,
        val input: FileInputStream,
    )
    private val sourceSessions = ConcurrentHashMap<String, SourceSession>()

    /// The pending result of an open tree picker.
    private var pendingFolderResult: MethodChannel.Result? = null

    /// The pending result of the multiple-document picker.
    private var pendingFilesResult: MethodChannel.Result? = null

    private var pendingSharedFiles: List<Map<String, Any?>> = emptyList()
    private var shareIntentChannel: MethodChannel? = null

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
                "pickFiles" -> pickFiles(result)
                "pickImages" -> pickImages(result)
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
                "openSource" -> openSource(call.argument<String>("uri"), call.argument<Number>("offset")?.toLong(), result)
                "readSourceChunk" -> readSourceChunk(call.argument<String>("sessionId"), call.argument<Number>("length")?.toInt(), result)
                "closeSource" -> closeSource(call.argument<String>("sessionId"), result)
                else -> result.notImplemented()
            }
        }

        pendingSharedFiles = (restorePendingSharedFiles() + sharedFilesFrom(intent)).distinctBy { it["uri"] }
        persistPendingSharedFiles()
        shareIntentChannel = MethodChannel(messenger, SHARE_INTENT_CHANNEL).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "consumePendingSharedFiles" -> {
                        // Flutter acknowledges only after the user chooses a
                        // destination and the upload has entered the durable queue.
                        result.success(pendingSharedFiles)
                    }
                    "acknowledgeSharedFiles" -> {
                        val acknowledged = (call.arguments as? List<*>)
                            ?.mapNotNull { it as? String }
                            ?.toSet()
                            .orEmpty()
                        synchronized(this) {
                            pendingSharedFiles = pendingSharedFiles.filterNot { it["uri"] in acknowledged }
                            persistPendingSharedFilesLocked()
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val files = sharedFilesFrom(intent)
        if (files.isEmpty()) return
        synchronized(this) {
            pendingSharedFiles = (pendingSharedFiles + files).distinctBy { it["uri"] }
            persistPendingSharedFilesLocked()
        }
        shareIntentChannel?.invokeMethod("sharedFiles", files)
    }

    /// Save pending share metadata between process launches. File data is stored separately.
    private fun persistPendingSharedFiles() {
        synchronized(this) { persistPendingSharedFilesLocked() }
    }

    private fun persistPendingSharedFilesLocked() {
        val array = JSONArray()
        pendingSharedFiles.forEach { item ->
            val json = JSONObject()
            item.forEach { (key, value) -> if (value != null) json.put(key, value) }
            array.put(json)
        }
        getSharedPreferences(SHARE_IMPORT_PREFS, Context.MODE_PRIVATE).edit()
            .putString(SHARE_IMPORTS_KEY, array.toString()).apply()
    }

    private fun restorePendingSharedFiles(): List<Map<String, Any?>> {
        val raw = getSharedPreferences(SHARE_IMPORT_PREFS, Context.MODE_PRIVATE)
            .getString(SHARE_IMPORTS_KEY, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).mapNotNull { index ->
                val json = array.optJSONObject(index) ?: return@mapNotNull null
                val uri = json.optString("uri").takeIf { it.isNotBlank() } ?: return@mapNotNull null
                val item = mutableMapOf<String, Any?>("uri" to uri,
                    "name" to json.optString("name", "Shared file"),
                    "mimeType" to json.optString("mimeType", "application/octet-stream"),
                    "size" to json.optLong("size", -1L))
                json.optString("localPath").takeIf { it.isNotBlank() && File(it).isFile }?.let { item["localPath"] = it }
                json.optString("stageError").takeIf { it.isNotBlank() }?.let { item["stageError"] = it }
                item
            }
        } catch (_: Exception) { emptyList() }
    }

    /// Extracts share streams and ClipData once per URI. File contents are read
    /// later in bounded ranges by the existing folder-picker content channel.
    private fun sharedFilesFrom(source: Intent?): List<Map<String, Any?>> {
        if (source == null ||
            (source.action != Intent.ACTION_SEND &&
             source.action != Intent.ACTION_SEND_MULTIPLE)
        ) return emptyList()

        val uris = linkedSetOf<Uri>()
        source.data?.let(uris::add)
        source.clipData?.let { clip ->
            for (index in 0 until clip.itemCount) {
                clip.getItemAt(index).uri?.let(uris::add)
            }
        }

        @Suppress("DEPRECATION")
        source.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let(uris::add)
        @Suppress("DEPRECATION")
        source.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.forEach(uris::add)

        return uris.map { uri ->
            // Keep a persistable read grant when the sending app explicitly offers one.
            val hasReadGrant =
                (source.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION) != 0
            val canPersist =
                (source.flags and Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION) != 0
            if (hasReadGrant && canPersist) {
                try {
                    contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION,
                    )
                } catch (_: SecurityException) {
                    // Most Sharesheet providers intentionally offer temporary grants.
                }
            }

            var displayName: String? = null
            var byteSize = -1L
            try {
                contentResolver.query(
                    uri,
                    arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
                    null,
                    null,
                    null,
                )?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val nameColumn =
                            cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        val sizeColumn = cursor.getColumnIndex(OpenableColumns.SIZE)
                        if (nameColumn >= 0 && !cursor.isNull(nameColumn)) {
                            displayName = cursor.getString(nameColumn)
                        }
                        if (sizeColumn >= 0 && !cursor.isNull(sizeColumn)) {
                            byteSize = cursor.getLong(sizeColumn)
                        }
                    }
                }
            } catch (_: Exception) {
                // Provider metadata is optional; the stream may still be readable.
            }

            if (byteSize < 0L) {
                try {
                    contentResolver.openAssetFileDescriptor(uri, "r")?.use { descriptor ->
                        byteSize = descriptor.length
                    }
                } catch (_: Exception) {
                    // Leave the size unknown; Flutter will reject the import cleanly.
                }
            }
            val mimeType = try {
                contentResolver.getType(uri) ?: "application/octet-stream"
            } catch (_: Exception) {
                "application/octet-stream"
            }
            mapOf(
                "uri" to uri.toString(),
                "name" to (displayName?.takeIf { it.isNotBlank() }
                    ?: uri.lastPathSegment?.substringAfterLast('/') ?: "Shared file"),
                "size" to byteSize,
                "mimeType" to mimeType,
            )
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
     * Opens Android's document picker and keeps provider URIs instead of
     * materialising the selected file into file_picker's cache directory.
     */
    private fun pickFiles(result: MethodChannel.Result) {
        if (pendingFolderResult != null || pendingFilesResult != null) {
            result.error("busy", "A document picker is already open", null)
            return
        }
        pendingFilesResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
        }
        try {
            startActivityForResult(intent, PICK_FILES_REQUEST_CODE)
        } catch (e: android.content.ActivityNotFoundException) {
            pendingFilesResult = null
            result.error("unavailable", "No document picker is available", null)
        }
    }

    /** Opens Android's native photo picker for both photos and videos. */
    private fun pickImages(result: MethodChannel.Result) {
        if (pendingFolderResult != null || pendingFilesResult != null) {
            result.error("busy", "A document picker is already open", null)
            return
        }
        pendingFilesResult = result
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Intent(MediaStore.ACTION_PICK_IMAGES).apply {
                // ACTION_PICK_IMAGES treats */* as both image/* and video/*.
                type = "*/*"
                putExtra(
                    MediaStore.EXTRA_PICK_IMAGES_MAX,
                    MediaStore.getPickImagesMaxLimit().coerceAtMost(50).coerceAtLeast(2),
                )
            }
        } else {
            // Older Android versions use SAF with a visual-media allow-list.
            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/*", "video/*"))
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
                )
            }
        }
        try {
            startActivityForResult(intent, PICK_IMAGES_REQUEST_CODE)
        } catch (e: android.content.ActivityNotFoundException) {
            pendingFilesResult = null
            result.error("unavailable", "No photo picker is available", null)
        }
    }

    /**
     * Queries metadata only. File contents stay at the selected document
     * provider and are fetched in bounded ranges by readSourceRange().
     */
    private fun describeDocument(uri: Uri): Map<String, Any> {
        var name = uri.lastPathSegment?.substringAfterLast('/') ?: "file"
        var size = -1L
        contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameIndex >= 0) name = cursor.getString(nameIndex) ?: name
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) {
                    size = cursor.getLong(sizeIndex)
                }
            }
        }
        if (size < 0) {
            contentResolver.openAssetFileDescriptor(uri, "r")?.use { descriptor ->
                size = descriptor.length
            }
        }
        require(size >= 0) {
            "The selected provider did not report the file size for $name"
        }
        return mapOf(
            "uri" to uri.toString(),
            "name" to name,
            "size" to size,
        )
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

    /** Open one provider stream per upload chunk; seek/skip only once. */
    private fun openSource(uri: String?, offset: Long?, result: MethodChannel.Result) {
        if (uri.isNullOrEmpty() || offset == null || offset < 0) {
            result.error("invalid", "Invalid source URI or offset", null)
            return
        }
        sourceExecutor.execute {
            var descriptor: ParcelFileDescriptor? = null
            var input: FileInputStream? = null
            try {
                val openedDescriptor = contentResolver.openFileDescriptor(Uri.parse(uri), "r")
                    ?: throw IllegalStateException("The document is no longer available")
                descriptor = openedDescriptor
                val openedInput = FileInputStream(openedDescriptor.fileDescriptor)
                input = openedInput
                try { openedInput.channel.position(offset) } catch (_: Exception) { skipFully(openedInput, offset) }
                val sessionId = UUID.randomUUID().toString()
                sourceSessions[sessionId] = SourceSession(openedDescriptor, openedInput)
                descriptor = null
                input = null
                runOnUiThread { result.success(sessionId) }
            } catch (error: Exception) {
                try { input?.close() } catch (_: Exception) {}
                try { descriptor?.close() } catch (_: Exception) {}
                runOnUiThread { result.error("open_failed", error.message ?: "The document could not be opened", null) }
            }
        }
    }

    /** Reads the next sequential range from an open provider stream. */
    private fun readSourceChunk(sessionId: String?, length: Int?, result: MethodChannel.Result) {
        if (sessionId.isNullOrEmpty() || length == null || length < 0 || length > 4 * 1024 * 1024) {
            result.error("invalid", "Invalid source session or chunk length", null)
            return
        }
        sourceExecutor.execute {
            try {
                val session = sourceSessions[sessionId] ?: throw IllegalStateException("The source session has expired")
                val bytes = synchronized(session) { readExactly(session.input, length) }
                runOnUiThread { result.success(bytes) }
            } catch (error: Exception) {
                runOnUiThread { result.error("read_failed", error.message ?: "The document could not be read", null) }
            }
        }
    }

    /** Releases an open provider stream. */
    private fun closeSource(sessionId: String?, result: MethodChannel.Result) {
        if (sessionId.isNullOrEmpty()) { result.success(null); return }
        sourceExecutor.execute {
            val session = sourceSessions.remove(sessionId)
            try { session?.input?.close() } catch (_: Exception) {}
            try { session?.descriptor?.close() } catch (_: Exception) {}
            runOnUiThread { result.success(null) }
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
        if (requestCode == PICK_FILES_REQUEST_CODE || requestCode == PICK_IMAGES_REQUEST_CODE) {
            val result = pendingFilesResult ?: return
            pendingFilesResult = null
            if (resultCode != Activity.RESULT_OK || data == null) {
                result.success(emptyList<Any>())
                return
            }
            val uris = ArrayList<Uri>()
            val clip = data.clipData
            if (clip != null) {
                for (index in 0 until clip.itemCount) {
                    clip.getItemAt(index).uri?.let(uris::add)
                }
            } else {
                data.data?.let(uris::add)
            }
            if (uris.isEmpty()) {
                result.success(emptyList<Any>())
                return
            }
            // ACTION_OPEN_DOCUMENT grants persistable read access. This lets
            // queued uploads resume when the app is reopened.
            for (uri in uris) {
                try {
                    contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION,
                    )
                } catch (_: SecurityException) {
                    // Some providers expose session-only grants; foreground
                    // uploads can still read those while the picker activity
                    // has handed control back to this app.
                }
            }
            folderExecutor.execute {
                try {
                    val files = uris.map(::describeDocument)
                    runOnUiThread { result.success(files) }
                } catch (e: Exception) {
                    runOnUiThread {
                        result.error(
                            "metadata_failed",
                            e.message ?: "The selected files could not be inspected",
                            null,
                        )
                    }
                }
            }
            return
        }
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
            result.error(
                "persist_failed",
                "This folder provider cannot keep access after NexaDrive closes. Choose a folder from Android Files.",
                null,
            )
            return
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

    override fun onDestroy() {
        sourceSessions.keys.toList().forEach { id ->
            val session = sourceSessions.remove(id) ?: return@forEach
            try { session.input.close() } catch (_: Exception) {}
            try { session.descriptor.close() } catch (_: Exception) {}
        }
        super.onDestroy()
    }

    companion object {
        private const val UPDATER_CHANNEL = "nexadrive/updater"
        private const val APP_LOCK_CHANNEL = "nexadrive/app_lock"
        private const val FOLDER_PICKER_CHANNEL = "nexadrive/folder_picker"
        private const val SHARE_INTENT_CHANNEL = "nexadrive/share_intents"
        private const val SHARE_IMPORT_PREFS = "nexadrive_share_imports"
        private const val SHARE_IMPORTS_KEY = "pending"
        private const val PICK_FILES_REQUEST_CODE = 7412
        private const val PICK_IMAGES_REQUEST_CODE = 7413
        const val ACTION_INSTALL_STATUS = "io.nexadrive.app.INSTALL_STATUS"
    }
}
