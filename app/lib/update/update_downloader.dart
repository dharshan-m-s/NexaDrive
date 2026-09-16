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

  /// Downloads [info] and verifies size + SHA-256 before returning.
  ///
  /// [onProgress] reports signed 64-bit byte counts (0..total). Return true
  /// from [isCancelled] to abort mid-stream; a cancelled download cleans up its
  /// partial file and surfaces [UpdateErrorKind.cancelled].
  Future<DownloadedArtifact> download(
    ArtifactInfo info, {
    required String artifactFileName,
    required String installerKind,
    void Function(int received, int? total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final uri = _source.resolveArtifact(info);
    final dir = cacheProvider?.call() ?? await cacheDirectory();
    final safeName = sanitizeFileName(artifactFileName);
    final part = File('${dir.path}/$safeName.part');
    final finalFile = File('${dir.path}/$safeName');
    if (part.existsSync()) {
      try {
        await part.delete();
      } catch (_) {}
    }

    final request = http.Request('GET', uri);
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

    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      throw UpdateException(
        UpdateErrorKind.http,
        'Download failed: the server returned HTTP ${response.statusCode}.',
      );
    }

    final total = response.contentLength;
    final expected = info.size;
    if (total != null && total >= 0 && total != expected) {
      await response.stream.drain<void>();
      throw const UpdateException(
        UpdateErrorKind.sizeMismatch,
        'The download is a different size than the release manifest says.',
      );
    }

    IOSink? sink;
    final accumulator = _DigestAccumulator();
    var received = 0;
    var finished = false;

    try {
      sink = part.openWrite();
      final conversion = sha256.startChunkedConversion(accumulator);
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
    } on UpdateException {
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
}