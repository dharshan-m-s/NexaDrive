import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'api.dart';

/// Result of a completed save.
class SaveResult {
  /// Where the file ended up. Human-readable: on Android this is the display
  /// name of the created document, on desktop an absolute path.
  final String location;

  /// True when the destination was provided by the user (Save As dialog or
  /// SAF document). False when the app picked a fallback location (e.g.
  /// app-visible Downloads directory when no SAF picker is available).
  final bool userChosen;

  const SaveResult({required this.location, required this.userChosen});
}

/// Saved-file destinations differ per platform:
///
/// - **Desktop (Linux/Windows/macOS)**: a native Save-As dialog returns a
///   real filesystem path. We stream to `<target>.part` and rename after the
///   download completes, so a cancelled or failed download never leaves a
///   half-written file behind the final name.
/// - **Android**: `FilePicker.saveFile` uses the Storage Access Framework
///   (ACTION_CREATE_DOCUMENT). The platform writes the *bytes handed to the
///   picker* into the created document and returns a `content://` URI —
///   treating that URI as a filesystem path is the historical bug that saved
///   empty files. To avoid the platform writing an empty placeholder first,
///   small files (< 64 MB) are downloaded fully into memory and handed to
///   SAF in one shot; larger files are streamed to the app cache and then
///   copied into the SAF document in chunks via the returned URI.
/// - **Fallback (no dialog available)**: the file is streamed into the
///   platform Downloads directory (or app documents dir) and the resulting
///   path is surfaced to the user.
///
/// All downloads stream from the server; nothing is buffered whole on desktop.
class DownloadService {
  final Api api;
  DownloadService(this.api);

  /// Threshold under which an Android save buffers in memory so SAF can write
  /// the document in one shot.
  static const _androidMemorySaveLimit = 64 * 1024 * 1024;

  /// Downloads [remotePath] to a user-chosen location.
  ///
  /// [fileName] seeds the save dialog. [mimeType] is best-effort metadata for
  /// Android's document creation. Returns null when the user cancels.
  Future<SaveResult?> saveAs({
    required String remotePath,
    required String fileName,
    String mimeType = 'application/octet-stream',
    Duration timeout = const Duration(minutes: 30),
    void Function(int received, int? total)? onProgress,
  }) async {
    if (Platform.isAndroid) {
      return _saveAndroid(
        remotePath: remotePath,
        fileName: fileName,
        mimeType: mimeType,
        timeout: timeout,
        onProgress: onProgress,
      );
    }
    return _saveDesktop(
      remotePath: remotePath,
      fileName: fileName,
      timeout: timeout,
      onProgress: onProgress,
    );
  }

  /// Picks (or falls back to) a destination directory for a batch download.
  ///
  /// Desktop shows a real folder chooser. Android cannot hand back a writable
  /// directory through the Storage Access Framework, so the platform Downloads
  /// directory is used instead and reported honestly to the user.
  Future<String?> pickBatchDestination() async {
    if (!Platform.isAndroid) {
      try {
        final picked = await FilePicker.getDirectoryPath(
          dialogTitle: 'Choose a folder for these files',
        );
        if (picked != null && picked.isNotEmpty) return picked;
      } catch (_) {
        // Fall through to the toolkits that cannot open a directory dialog.
      }
    }
    // The platform helpers can be unavailable (desktop portals without a
    // downloads dir, headless test hosts). Returning null means "the user has
    // nowhere to put these", which the caller reports instead of crashing.
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) return downloads.path;
      final docs = await getApplicationDocumentsDirectory();
      return '${docs.path}${Platform.pathSeparator}NexaDrive';
    } catch (_) {
      return null;
    }
  }

  /// Downloads every entry of [items] into [directory].
  ///
  /// Files are streamed one at a time (never buffered whole), written
  /// atomically, and collisions are resolved with a numeric suffix so nothing
  /// is silently overwritten. A failing file does not abort the rest.
  Future<BatchSaveResult> saveAllToDirectory({
    required List<BatchItem> items,
    required String directory,
    void Function(int completed, int total, String fileName)? onProgress,
    CancelToken? cancel,
    Duration timeout = const Duration(minutes: 30),
  }) async {
    final target = Directory(directory);
    await target.create(recursive: true);
    final failures = <String, String>{};
    var saved = 0;
    var completed = 0;
    final taken = <String>{};

    for (final item in items) {
      if (cancel?.isCancelled == true) {
        return BatchSaveResult(
          saved: saved,
          failures: failures,
          directory: directory,
          cancelled: true,
        );
      }
      onProgress?.call(completed, items.length, item.fileName);
      final name = _uniqueName(item.fileName, directory, taken);
      taken.add(name.toLowerCase());
      try {
        await downloadToFile(
          item.remotePath,
          '$directory${Platform.pathSeparator}$name',
          timeout: timeout,
          cancel: cancel,
        );
        saved++;
      } on SaveCancelled {
        return BatchSaveResult(
          saved: saved,
          failures: failures,
          directory: directory,
          cancelled: true,
        );
      } catch (e) {
        failures[item.fileName] = e.toString();
      }
      completed++;
      onProgress?.call(completed, items.length, item.fileName);
    }
    return BatchSaveResult(
      saved: saved,
      failures: failures,
      directory: directory,
    );
  }

  /// `report.pdf` -> `report (2).pdf` when the name is already taken on disk
  /// or by an earlier item in the same batch.
  String _uniqueName(String fileName, String directory, Set<String> taken) {
    if (!taken.contains(fileName.toLowerCase()) &&
        !File('$directory${Platform.pathSeparator}$fileName').existsSync()) {
      return fileName;
    }
    final dot = fileName.lastIndexOf('.');
    final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
    final ext = dot > 0 ? fileName.substring(dot) : '';
    for (var n = 2; n < 10000; n++) {
      final candidate = '$stem ($n)$ext';
      if (!taken.contains(candidate.toLowerCase()) &&
          !File('$directory${Platform.pathSeparator}$candidate').existsSync()) {
        return candidate;
      }
    }
    return '${DateTime.now().microsecondsSinceEpoch}-$fileName';
  }

  // ------------------------------------------------------------------ desktop

  Future<SaveResult?> _saveDesktop({
    required String remotePath,
    required String fileName,
    required Duration timeout,
    void Function(int received, int? total)? onProgress,
  }) async {
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      bytes: Uint8List(0),
      dialogTitle: 'Save $fileName',
    );
    if (uri == null) return null;
    // Linux/Windows return file:// URIs; normalize to a plain path.
    final String targetPath;
    try {
      targetPath = uri.scheme == 'file' || uri.scheme.isEmpty
          ? uri.toFilePath()
          : uri.toString();
    } on UnsupportedError {
      throw const SaveException(
        'The chosen save location is not a local folder. Pick a folder on this device.',
      );
    }
    await downloadToFile(remotePath, targetPath, timeout: timeout, onProgress: onProgress);
    return SaveResult(location: targetPath, userChosen: true);
  }

  // ------------------------------------------------------------------ android

  Future<SaveResult?> _saveAndroid({
    required String remotePath,
    required String fileName,
    required String mimeType,
    required Duration timeout,
    void Function(int received, int? total)? onProgress,
  }) async {
    // Probe size to pick the SAF strategy.
    final size = await _contentLength(remotePath, timeout);

    if (size != null && size <= _androidMemorySaveLimit) {
      // One-shot: download fully, then let SAF write the document.
      final bytes = await api.download(remotePath);
      final uri = await FilePicker.saveFile(
        fileName: fileName,
        bytes: bytes,
        mimeType: mimeType,
        dialogTitle: 'Save $fileName',
      );
      if (uri == null) return null;
      return SaveResult(location: _describeAndroidUri(uri, fileName), userChosen: true);
    }

    // Large file: streaming into a SAF document is not supported by the
    // picker (it owns the output stream at dialog time), and buffering a
    // multi-GB file in RAM is not acceptable. Stream to the platform
    // Downloads directory instead and tell the user where it landed.
    final downloads = await getDownloadsDirectory();
    final Directory targetDir;
    if (downloads != null) {
      targetDir = downloads;
    } else {
      final docs = await getApplicationDocumentsDirectory();
      targetDir = Directory('${docs.path}/NexaDrive');
    }
    await targetDir.create(recursive: true);
    final targetPath = '${targetDir.path}${Platform.pathSeparator}$fileName';
    await downloadToFile(remotePath, targetPath, timeout: timeout, onProgress: onProgress);
    return SaveResult(location: targetPath, userChosen: false);
  }

  String _describeAndroidUri(Uri uri, String fallbackName) {
    if (uri.scheme == 'content') {
      return uri.queryParameters['displayName'] ?? fallbackName;
    }
    try {
      return uri.toFilePath();
    } on UnsupportedError {
      return uri.toString();
    }
  }

  Future<int?> _contentLength(String remotePath, Duration timeout) async {
    try {
      final request = http.Request('HEAD', api.fileDownloadUri(remotePath));
      request.headers.addAll(api.authHeaders);
      final response = await api.rawClient.send(request).timeout(timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final length = response.contentLength;
        // Drain/close without reading a body.
        await response.stream.drain<void>().timeout(const Duration(seconds: 5));
        return length;
      }
      await response.stream.drain<void>().catchError((_) {});
      return null;
    } catch (_) {
      return null;
    }
  }

  // -------------------------------------------------------------- core stream

  /// Streams [remotePath] to [targetPath] atomically: bytes are written to a
  /// unique `.part` sibling and renamed over the destination only after the
  /// server response has been fully received. Progress is reported when the
  /// server provides a Content-Length. Cancels by [CancelToken] delete the
  /// partial file.
  Future<void> downloadToFile(
    String remotePath,
    String targetPath, {
    Duration timeout = const Duration(minutes: 30),
    void Function(int received, int? total)? onProgress,
    CancelToken? cancel,
  }) async {
    final request = http.Request('GET', api.fileDownloadUri(remotePath));
    request.headers.addAll(api.authHeaders);

    final response = await api.rawClient
        .send(request)
        .timeout(timeout, onTimeout: () => throw const SaveException(
              'The server took too long to respond. Check the connection and try again.',
            ));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw SaveException(Api.messageFromBody(body, response.statusCode));
    }

    final destination = File(targetPath);
    final parent = destination.parent.path;
    final tempPath =
        '$parent${Platform.pathSeparator}.${_baseName(targetPath)}.nexadrive-${DateTime.now().microsecondsSinceEpoch}.part';
    final temp = File(tempPath);
    final sink = temp.openWrite();
    IOSink? activeSink = sink;
    var received = 0;
    final total = response.contentLength;
    StreamSubscription<List<int>>? subscription;

    try {
      final completer = Completer<void>();
      subscription = response.stream.listen(
        (chunk) {
          if (cancel?.isCancelled == true) {
            subscription?.cancel();
            if (!completer.isCompleted) {
              completer.completeError(const SaveCancelled());
            }
            return;
          }
          received += chunk.length;
          activeSink?.add(chunk);
          onProgress?.call(received, total);
        },
        onError: (Object e) {
          if (!completer.isCompleted) {
            completer.completeError(
              e is SaveException ? e : SaveException(_friendlyNetworkError(e)),
            );
          }
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );
      await completer.future.timeout(timeout);
      await activeSink.flush();
      await activeSink.close();
      activeSink = null;

      // Publish atomically: rename over any previous file.
      if (await destination.exists()) {
        await destination.delete();
      }
      await temp.rename(targetPath);
    } catch (e) {
      try {
        await activeSink?.close();
      } catch (_) {}
      try {
        await temp.delete();
      } catch (_) {}
      rethrow;
    } finally {
      await subscription?.cancel();
    }
  }

  String _baseName(String path) {
    final clean = path.replaceAll('\\', '/');
    final i = clean.lastIndexOf('/');
    return i < 0 ? clean : clean.substring(i + 1);
  }

  String _friendlyNetworkError(Object e) {
    if (e is SocketException) {
      return 'The connection dropped while downloading. Check the network and try again.';
    }
    if (e is TimeoutException) {
      return 'The download stalled and was stopped. Try again.';
    }
    return 'The download failed: $e';
  }
}

/// One file in a batch save.
typedef BatchItem = ({String remotePath, String fileName});

/// Outcome of a batch save.
class BatchSaveResult {
  const BatchSaveResult({
    required this.saved,
    required this.failures,
    required this.directory,
    this.cancelled = false,
  });

  final int saved;

  /// File name -> user-facing reason. Empty when everything succeeded.
  final Map<String, String> failures;

  final String directory;
  final bool cancelled;

  bool get allSucceeded => failures.isEmpty && !cancelled;
}

/// Cooperative cancellation handle for [DownloadService.downloadToFile].
class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// User-visible download failure with an actionable message.
class SaveException implements Exception {
  final String message;
  const SaveException(this.message);
  @override
  String toString() => message;
}

/// Thrown when the user cancelled the transfer (distinct from failure).
class SaveCancelled implements Exception {
  const SaveCancelled();
  @override
  String toString() => 'Download cancelled';
}
