package io.nexadrive.app

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import java.io.File

/**
 * Host-side bridge for the Storage Access Framework folder picker.
 *
 * Android has no "give me a folder path" API: the system picker hands back a
 * tree URI, and the bytes behind it are only reachable through the content
 * resolver. The Flutter side therefore asks for a tree, and this bridge
 * materialises it into the app cache so the upload queue can stream it with
 * ordinary file I/O.
 *
 * The bridge never asks for a storage permission: the user grants access to
 * exactly one tree through the system picker, and that grant is what makes
 * the tree readable.
 */
internal class FolderPickerBridge(private val context: Context) {

    companion object {
        const val REQUEST_CODE = 10021
    }

    /** One file found inside a picked tree. */
    data class Entry(
        val relativePath: String,
        val name: String,
        val size: Long,
        val uri: String,
    )

    private val resolver: ContentResolver get() = context.contentResolver

    /**
     * Reads every document of the tree [treeUri].
     *
     * The walk is breadth-first and bounded: a provider that reports a huge
     * tree must not be able to stall the picker.
     */
    fun readTree(treeUri: Uri, maxEntries: Int = 20_000): List<Entry> {
        val entries = mutableListOf<Entry>()
        val documentId = try {
            DocumentsContract.getTreeDocumentId(treeUri)
        } catch (e: Exception) {
            return entries
        }
        val queue = ArrayDeque<Pair<String, String>>()
        queue.add(documentId to "")
        while (queue.isNotEmpty()) {
            val (parentId, parentPath) = queue.removeFirst()
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
                treeUri,
                parentId,
            )
            val cursor = try {
                resolver.query(
                    childrenUri,
                    arrayOf(
                        DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                        DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                        DocumentsContract.Document.COLUMN_MIME_TYPE,
                        DocumentsContract.Document.COLUMN_SIZE,
                    ),
                    null,
                    null,
                    null,
                )
            } catch (e: Exception) {
                null
            } ?: continue
            cursor.use { c ->
                while (c.moveToNext() && entries.size < maxEntries) {
                    val id = c.getString(0) ?: continue
                    val name = c.getString(1) ?: continue
                    val mime = c.getString(2) ?: ""
                    val size = if (c.isNull(3)) 0L else c.getLong(3)
                    val childUri = DocumentsContract.buildDocumentUriUsingTree(
                        treeUri,
                        id,
                    )
                    val relative =
                        if (parentPath.isEmpty()) name else "$parentPath/$name"
                    if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                        queue.add(id to relative)
                    } else {
                        entries.add(Entry(relative, name, size, childUri.toString()))
                    }
                }
            }
        }
        return entries
    }

    /**
     * Copies the tree [treeUri] into [target] and returns the copied files.
     *
     * The copy happens on a background executor, so a large tree never blocks
     * the platform thread.
     */
    fun materialize(treeUri: Uri, target: File): List<Map<String, Any?>> {
        val copied = mutableListOf<Map<String, Any?>>()
        for (entry in readTree(treeUri)) {
            val destination = File(target, entry.relativePath)
            destination.parentFile?.mkdirs()
            try {
                val input = resolver.openInputStream(Uri.parse(entry.uri)) ?: continue
                input.use { source ->
                    destination.outputStream().use { sink ->
                        source.copyTo(sink, 256 * 1024)
                    }
                }
                copied.add(
                    mapOf(
                        "path" to entry.relativePath,
                        "name" to entry.name,
                        "size" to destination.length(),
                        "localPath" to destination.absolutePath,
                    ),
                )
            } catch (e: Exception) {
                // A document that cannot be read is skipped; the rest of the
                // tree still uploads.
                destination.delete()
            }
        }
        return copied
    }

    /** The display name of the picked tree, used as the top-level folder. */
    fun displayName(treeUri: Uri): String {
        return try {
            val id = DocumentsContract.getTreeDocumentId(treeUri)
            val cursor = resolver.query(
                DocumentsContract.buildDocumentUriUsingTree(treeUri, id),
                arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                null,
                null,
                null,
            )
            cursor?.use { c ->
                if (c.moveToFirst()) return c.getString(0) ?: "folder"
            }
            "folder"
        } catch (e: Exception) {
            "folder"
        }
    }
}
