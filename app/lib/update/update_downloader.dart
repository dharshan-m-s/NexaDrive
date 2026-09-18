import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'update_manifest.dart';
import 'update_source.dart';

/// A fully downloaded and verified artifact.
class DownloadedArtifact {
  final File file;
  final String sha256Hex;
  final int size;
  final String installerKind;

  const DownloadedArtifact({
    required this.file,
    required this.sha256Hex,
    required this.size,
    required this.installerKind,
  });
}

/// Accumulates the final `Digest` produced by a chunked SHA-256 conversion.
class _DigestAccumulator implements Sink<Digest> {
  Digest? result;

  @override
  void add(Digest data) {
    result = data;
  }

  @override
  void close() {}
}

/// Streams an artifact to the app's private cache, hashing as it reads.
///
/// Guarantees:
///  - the file lands under `nexadrive_updates/` in the temp directory;
///  - the SHA-256 is computed incrementally over the exact bytes written;
///  - nothing is committed to its final name until size *and* checksum match;
///  - a failed/interrupted/cancelled download leaves only a `.part` file that
///    the next attempt or [UpdateCache.prune] removes.
class UpdateDownloader {
  final http.Client _client;
  final UpdateSource _source;
  final Duration timeout;
  final Duration idleTimeout;
  final Directory Function()? cacheProvider;

  UpdateDownloader({
    http.Client? client,
    UpdateSource? source,
    this.timeout = const Duration(minutes: 10),
    this.idleTimeout = const Duration(seconds: 60),
    this.cacheProvider,
  })  : _client = RedirectGuardedClient(client ?? http.Client()),
        _source = source ?? UpdateSource();

  /// Where final installers live. Shared by cache management.
  ///
  /// Uses the platform's app-private temp/cache directory (per-user on
  /// desktop, private to the app on Android, where it also matches the
  /// FileProvider `<cache-path>` exposed to the system package installer).
  /// Falls back to the OS temp dir in bare VMs/tests where the plugin
  /// registry is unavailable.
  static Future<Directory> cacheDirectory() async {
    Directory tmp;
    try {
      tmp = await getTemporaryDirectory();
    } catch (_) {
      tmp = Directory.systemTemp;
    }
    if (!tmp.existsSync()) {
      throw const UpdateException(
        UpdateErrorKind.blocked,
        'No writable cache directory is available.',
      );
    }
    final dir = Directory('${tmp.path}/nexadrive_updates');
    await dir.create(recursive: true);
    return dir;
  }

  /// Reduces a manifest-supplied artifact name to a safe flat basename:
  /// no directory separators (no traversal out of the update cache), no
  /// control characters, no reserved `.` / `..` entries.
  static String sanitizeFileName(String raw) {
    var name = raw.replaceAll('\\', '/');
    final slash = name.lastIndexOf('/');
    if (slash >= 0) name = name.substring(slash + 1);
    name = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (name.isEmpty || name == '.' || name == '..') {
      name = 'nexadrive-update.bin';
    }
    return name;
  }

  /// Deletes the `.part` file belonging to [artifactFileName], if one exists.
  ///
  /// This is how a *paused* download is thrown away: the checkpoint is
  /// intentionally left on disk by a pause, so discarding it must be explicit.
  /// Returns `true` when a file was actually removed.
  Future<bool> discardPartial({required String artifactFileName}) async {
    final dir = cacheProvider?.call() ?? await cacheDirectory();
    final part = File('${dir.path}/${sanitizeFileName(artifactFileName)}.part');
    if (!part.existsSync()) return false;
    try {
      await part.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Downloads [info] and verifies size + SHA-256 before returning.
  ///
  /// [onProgress] reports signed 64-bit byte counts (0..total). Return true
  /// from [isCancelled] to abort mid-stream; a cancelled download cleans up its
  /// partial file and surfaces [UpdateErrorKind.cancelled].
  ///
  /// Return true from [isPaused] to *suspend* instead: the partial file is kept
  /// intact and [UpdateErrorKind.paused] is raised carrying the checkpoint in
  /// [UpdateException.offset]. Pass that value back as [resumeFrom] to continue
  /// with an HTTP `Range` request rather than re-downloading from zero.
  ///
  /// A [resumeFrom] checkpoint is only honoured when it matches the byte length
  /// actually on disk; anything else restarts cleanly, and a server that
  /// ignores `Range` and answers `200` is detected and restarted rather than
  /// appended to.
  Future<DownloadedArtifact> download(
    ArtifactInfo info, {
    required String artifactFileName,
    required String installerKind,
    void Function(int received, int? total)? onProgress,
    bool Function()? isCancelled,
    bool Function()? isPaused,
    int resumeFrom = 0,
  }) async {
    final uri = _source.resolveArtifact(info);
    final dir = cacheProvider?.call() ?? await cacheDirectory();
    final safeName = sanitizeFileName(artifactFileName);
    final part = File('${dir.path}/$safeName.part');
    final finalFile = File('${dir.path}/$safeName');

    // Trust a checkpoint only when the bytes are really there, and only when it
    // is a genuine prefix of the artifact. A truncated, oversized or unexpected
    // partial restarts from zero instead of silently corrupting the result.
    var received = 0;
    if (resumeFrom > 0 &&
        resumeFrom < info.size &&
        part.existsSync() &&
        part.lengthSync() == resumeFrom) {
      received = resumeFrom;
    }
    if (received == 0 && part.existsSync()) {
      try {
        await part.delete();
      } catch (_) {}
    }

    final request = http.Request('GET', uri);
    if (received > 0) request.headers['Range'] = 'bytes=$received-';

    final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(timeout);
    } on SocketException {
      throw const UpdateException(
        UpdateErrorKind.network,
        'Download failed: no internet connection.',
      );
    } on TimeoutException {
      throw const UpdateException(
        UpdateErrorKind.network,
        'Download timed out.',
      );
    } on http.ClientException {
      throw const UpdateException(
        UpdateErrorKind.network,
        'Download could not connect.',
      );
    }

    final expected = info.size;

    // 206 = the server honoured our Range request. 200 to a *ranged* request
    // means it ignored the header and is resending the whole artifact, so the
    // partial is discarded and the hash restarts from zero.
    if (received > 0 && response.statusCode == 200) {
      received = 0;
      try {
        if (part.existsSync()) await part.delete();
      } catch (_) {}
    }

    if (response.statusCode != 200 && response.statusCode != 206) {
      await response.stream.drain<void>();
      throw UpdateException(
        UpdateErrorKind.http,
        'Download failed: the server returned HTTP ${response.statusCode}.',
      );
    }

    final total = response.contentLength;
    final expectedBody = expected - received;
    if (total != null && total >= 0 && total != expectedBody) {
      await response.stream.drain<void>();
      throw const UpdateException(
        UpdateErrorKind.sizeMismatch,
        'The download is a different size than the release manifest says.',
      );
    }

    IOSink? sink;
    final accumulator = _DigestAccumulator();
    var finished = false;

    try {
      final conversion = sha256.startChunkedConversion(accumulator);
      if (received > 0) {
        // Re-hash the bytes already on disk so the final digest still covers
        // the whole artifact. Streamed in chunks, so memory stays bounded
        // regardless of how large the resumed file is.
        await for (final chunk in part.openRead(0, received)) {
          conversion.add(chunk);
        }
      }
      sink = part.openWrite(
        mode: received > 0 ? FileMode.append : FileMode.write,
      );
      final completer = Completer<void>();
      var lastProgress = DateTime.now();
      Timer? watchdog;
      var watchdogFired = false;

      void fail(Object error) {
        if (finished) return;
        final scheduled = watchdog;
        if (scheduled != null) {
          scheduled.cancel();
        }
        finished = true;
        completer.completeError(error);
      }

      late final StreamSubscription<List<int>> subscription;
      subscription = response.stream.listen(
        (List<int> chunk) {
          if (isCancelled?.call() == true) {
            fail(const UpdateException(
              UpdateErrorKind.cancelled,
              'Download cancelled.',
            ));
            subscription.cancel().ignore();
            sink!.close().ignore();
            return;
          }
          if (isPaused?.call() == true) {
            // Suspend, keeping the partial. The outer catch flushes and closes
            // the sink so the file is exactly `received` bytes — the value
            // reported as the resumable checkpoint.
            fail(UpdateException(
              UpdateErrorKind.paused,
              'Download paused.',
              offset: received,
            ));
            subscription.cancel().ignore();
            return;
          }
          sink!.add(chunk);
          conversion.add(chunk);
          received += chunk.length;
          lastProgress = DateTime.now();
          if (received > expected) {
            fail(const UpdateException(
              UpdateErrorKind.sizeMismatch,
              'The download exceeded the expected size.',
            ));
            subscription.cancel().ignore();
            return;
          }
          onProgress?.call(received, expected);
        },
        onError: (Object error, StackTrace stack) {
          fail(const UpdateException(
            UpdateErrorKind.network,
            'The connection was interrupted.',
          ));
        },
        onDone: () async {
          try {
            if (received > expected) {
              fail(const UpdateException(
                UpdateErrorKind.sizeMismatch,
                'The download exceeded the expected size.',
              ));
              return;
            }
            conversion.close();
            await sink!.flush();
            await sink!.close();
            finished = true;
            watchdog?.cancel();
            completer.complete();
          } catch (_) {
            fail(const UpdateException(
              UpdateErrorKind.blocked,
              'Could not write the downloaded file.',
            ));
          }
        },
        cancelOnError: true,
      );

      // Idle watchdog: if the stream stalls for `idleTimeout` with zero bytes
      // arriving (server dropped the connection without a close, NAT timeout,
      // flaky carrier), abort the download so the Update Center always reaches
      // a terminal state instead of hanging on "Downloading…" forever.
      watchdog = Timer.periodic(const Duration(seconds: 5), (_) {
        if (finished || watchdogFired) return;
        if (DateTime.now().difference(lastProgress) >= idleTimeout) {
          watchdogFired = true;
          subscription.cancel().ignore();
          sink!.close().ignore();
          fail(const UpdateException(
            UpdateErrorKind.network,
            'The download stalled and was stopped.',
          ));
        }
      });

      await completer.future;

      if (received != expected) {
        throw const UpdateException(
          UpdateErrorKind.sizeMismatch,
          'The download ended early (size mismatch).',
        );
      }

      final digestHex = accumulator.result?.toString() ?? '';
      if (digestHex.isEmpty) {
        throw const UpdateException(
          UpdateErrorKind.network,
          'Download failed before any bytes arrived.',
        );
      }
      if (digestHex.toLowerCase() != info.sha256Hex) {
        throw const UpdateException(
          UpdateErrorKind.checksumMismatch,
          'The download failed verification (SHA-256 mismatch).',
        );
      }

      try {
        await part.rename(finalFile.path);
      } catch (_) {
        await part.copy(finalFile.path);
        await part.delete();
      }

      return DownloadedArtifact(
        file: finalFile,
        sha256Hex: digestHex.toLowerCase(),
        size: received,
        installerKind: installerKind,
      );
    } on UpdateException catch (e) {
      if (e.kind == UpdateErrorKind.paused) {
        // Deliberately keep the `.part` file: this is a resumable checkpoint,
        // not a failure. Flush first so its length equals `e.offset`.
        try {
          await sink?.flush();
        } catch (_) {}
        try {
          await sink?.close();
        } catch (_) {}
        rethrow;
      }
      await _cleanup(part, sink);
      rethrow;
    } catch (_) {
      await _cleanup(part, sink);
      throw const UpdateException(
        UpdateErrorKind.network,
        'Download failed unexpectedly.',
      );
    }
  }

  static Future<void> _cleanup(File part, IOSink? sink) async {
    try {
      await sink?.close();
    } catch (_) {}
    try {
      if (part.existsSync()) await part.delete();
    } catch (_) {}
  }
}

/// Bounded cache maintenance for downloaded installers.
class UpdateCache {
  /// Removes stale partials, prunes old installers past [maxBytes] (keeping
  /// the newest), and drops anything older than [maxAge] so a signed
  /// installer does not linger on disk indefinitely.
  static Future<void> prune({
    int maxBytes = 300 * 1024 * 1024,
    Duration maxAge = const Duration(days: 21),
  }) async {
    Directory dir;
    try {
      dir = await UpdateDownloader.cacheDirectory();
    } catch (_) {
      return;
    }
    if (!dir.existsSync()) return;

    final now = DateTime.now();
    final List<FileSystemEntity> files;
    try {
      files = dir.listSync(followLinks: false);
    } catch (_) {
      return;
    }

    // Stale partial downloads (>.part, older than 4 hours) are always removed.
    for (final p in files.where((f) => f.path.endsWith('.part'))) {
      try {
        if (now.difference(p.statSync().modified) >
            const Duration(hours: 4)) {
          File(p.path).deleteSync();
        }
      } catch (_) {}
    }

    final installers = files
        .where((f) => !f.path.endsWith('.part'))
        .whereType<File>()
        .toList();

    int total = 0;
    for (final f in installers) {
      try {
        total += f.lengthSync();
      } catch (_) {}
    }

    installers.sort((a, b) =>
        b.statSync().modified.compareTo(a.statSync().modified));

    for (final f in installers) {
      var expired = false;
      try {
        expired = now.difference(f.statSync().modified) > maxAge;
      } catch (_) {
        expired = true;
      }
      if (!expired && total <= maxBytes) break;
      try {
        total -= f.lengthSync();
        f.deleteSync();
      } catch (_) {}
    }
  }

  /// Deletes every file inside the update cache directory (installers,
  /// `.part` partials, leftover ZIP/APK downloads).
  ///
  /// Called once the install is confirmed so nothing lingers on disk. All
  /// operations are best-effort: a missing directory is not an error.
  static Future<void> clearAll() async {
    Directory dir;
    try {
      dir = await UpdateDownloader.cacheDirectory();
    } catch (_) {
      return;
    }
    if (!dir.existsSync()) return;
    final entries = dir.listSync(followLinks: false);
    for (final entry in entries) {
      try {
        if (entry is File) {
          entry.deleteSync();
        } else if (entry is Directory) {
          entry.deleteSync(recursive: true);
        }
      } catch (_) {}
    }
  }
}