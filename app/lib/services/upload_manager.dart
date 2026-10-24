import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'api.dart';
import 'content_source.dart';
import 'upload_item.dart';
import 'upload_store.dart';

/// A local file that is ready to be uploaded.
///
/// The queue works with plain values rather than picker objects so the same
/// code serves a local file, an Android document URI, and a test fixture.
class UploadSource {
  const UploadSource({
    required this.path,
    required this.name,
    required this.size,
    this.relativePath = '',
    this.temporary = false,
    this.sourceUri,
  });

  /// Absolute path of the file on this device, or its Android document URI
  /// when [sourceUri] is set.
  final String path;

  /// Android Storage Access Framework document URI, when this file came from
  /// a picked folder. Bytes are streamed from the provider and never copied
  /// into app storage.
  final String? sourceUri;

  /// Name the file should have on the server.
  final String name;

  /// Size in bytes.
  final int size;

  /// Path of the file inside the folder it was picked from, such as
  /// `2024/January`. It is appended to the destination folder so a picked
  /// folder keeps its nested structure on the server.
  final String relativePath;

  /// Whether the app owns the file and may delete it once the upload is done.
  final bool temporary;
}

/// The single owner of the upload queue.
///
/// Every screen reads the same queue through this object, so a transfer can
/// only ever be in one place: there is no second copy of the list, no second
/// worker, and no per-screen pause flag that could disagree with the queue's
/// own state.
///
/// The queue is file-backed, so it survives an app restart and can be picked
/// up again. The server owns the byte offset, so a resumed transfer always
/// continues exactly where it stopped.
class UploadManager extends ChangeNotifier {
  UploadManager._(this._store, {bool claimsForeground = true})
      : _claimsForeground = claimsForeground;

  /// Whether this instance is allowed to claim ownership of the queue.
  final bool _claimsForeground;

  /// The queue of this process. One instance, shared by every screen.
  static UploadManager? _current;

  /// The process-wide upload queue.
  ///
  /// The manager is created lazily because it needs a file to write its
  /// journal to, and that path is only known once the platform answers.
  static UploadManager get current {
    final existing = _current;
    if (existing != null) return existing;
    final created = UploadManager._(UploadStore(File(_journalPathFallback())));
    _current = created;
    unawaited(created._bootstrap());
    return created;
  }

  /// The queue of a background worker.
  ///
  /// A background worker never claims ownership: the foreground app owns the
  /// queue, and the worker only takes over when the app is really gone.
  static UploadManager background() {
    final existing = _current;
    if (existing != null) return existing;
    final created = UploadManager._(
      UploadStore(File(_journalPathFallback())),
      claimsForeground: false,
    );
    _current = created;
    unawaited(created._bootstrap());
    return created;
  }

  /// Test seam: installs a manager backed by [store].
  @visibleForTesting
  static void installForTesting(UploadManager manager) {
    _current = manager;
    if (!manager._readyCompleter.isCompleted) {
      manager._readyCompleter.complete();
    }
  }

  /// Creates a manager that writes its journal to [file].
  @visibleForTesting
  static UploadManager forTesting(File file) {
    final manager = UploadManager._(UploadStore(file));
    _current = manager;
    unawaited(manager._bootstrapForTesting());
    return manager;
  }

  /// Loads the journal of a test manager.
  Future<void> _bootstrapForTesting() async {
    await _reload();
    if (!_readyCompleter.isCompleted) _readyCompleter.complete();
  }

  /// The journal the queue is written to.
  UploadStore _store;

  /// The API client the queue uploads through.
  Api? _api;

  /// Every known item, keyed by id.
  final Map<String, UploadItem> _items = <String, UploadItem>{};

  /// Ids waiting for a worker slot, in the order they were queued.
  final List<String> _waiting = <String>[];

  /// Ids a worker is currently transferring.
  final Set<String> _active = <String>{};

  /// Cancellations that have been requested but not yet observed by a worker.
  final Set<String> _cancelled = <String>{};

  /// When the last journal line for an item was written, so progress is not
  /// written on every single chunk.
  final Map<String, DateTime> _lastPersisted = <String, DateTime>{};

  /// How many files may be transferred at the same time.
  int concurrency = 3;

  /// Chunk size used for the resumable chunk endpoint.
  ///
  /// 16 MB amortises connection setup, TLS and one fsync per chunk while
  /// keeping the worst-case re-send on a dropped connection tolerable.
  static const int chunkSize = 16 * 1024 * 1024;

  /// How many times a transfer is retried after a transient failure.
  static const int maxAttempts = 3;

  /// Backoff before the n-th retry, in seconds.
  static const List<int> backoffSeconds = <int>[2, 5, 10];

  /// Minimum interval between two progress writes of the same item.
  static const Duration progressInterval = Duration(milliseconds: 250);

  /// Whether the journal finished loading.
  bool _ready = false;

  /// Whether the manager finished loading.
  bool get isReady => _ready;

  /// A snapshot of every item in the queue.
  List<UploadItem> items() => _items.values.toList(growable: false);

  /// How many files still owe bytes to the server.
  int get pendingCount => _items.values
      .where((UploadItem item) =>
          item.state == UploadState.queued ||
          item.state == UploadState.uploading ||
          item.state == UploadState.retrying ||
          item.state == UploadState.paused)
      .length;

  /// How many transfers failed and can be retried.
  int get failedCount => _items.values
      .where((UploadItem item) => item.state == UploadState.failed)
      .length;

  /// Whether a worker is transferring right now.
  bool get isBusy => _active.isNotEmpty;

  /// Binds the queue to an API client.
  ///
  /// Called once the session exists. Re-binding to a different client (a new
  /// login) reloads the journal from disk.
  void attach(Api api) {
    if (identical(_api, api)) return;
    _api = api;
    unawaited(_reload());
  }

  /// Moves the journal to the platform's support directory and loads it.
  Future<void> _bootstrap() async {
    try {
      final file = await journalFile();
      if (file.path != _store.file.path) {
        await _store.dispose();
        _store = UploadStore(file);
      }
    } catch (_) {
      // Keep the fallback journal.
    }
    await _reload();
    // Older app versions copied folder uploads into the app cache. Remove
    // such copies when no queued item references them (for example after the
    // app was killed between copying a folder and persisting the queue).
    await _cleanupOwnedFolderCache();
    if (!_readyCompleter.isCompleted) _readyCompleter.complete();
  }

  /// Reloads are chained so two callers cannot interleave them.
  Future<void> _reloadChain = Future<void>.value();

  /// Loads the journal and picks the transfers back up.
  Future<void> _reload() {
    final next = _reloadChain.then((_) => _loadFromJournal());
    _reloadChain = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<void> _loadFromJournal() async {
    final loaded = await _store.load();
    _items
      ..clear()
      ..addEntries(
        loaded.map((UploadItem item) => MapEntry(item.id, item)),
      );
    _waiting.clear();
    for (final item in _items.values) {
      // A transfer that was running when the app died is picked back up.
      // The server holds the authoritative offset, so the worker asks for it
      // before sending anything.
      var current = item;
      if (current.state == UploadState.uploading ||
          current.state == UploadState.retrying) {
        current = current.copyWith(
          state: UploadState.queued,
          clearError: true,
        );
        _items[item.id] = current;
        await _persist(current);
      }
      // Use the post-transition state: an interrupted transfer is queued now
      // and must join the waiting list, or nothing would ever pick it up.
      if (current.state == UploadState.queued) _waiting.add(item.id);
    }
    _ready = true;
    notifyListeners();
    _pump();
  }

  /// Completes once the journal has been loaded.
  final Completer<void> _readyCompleter = Completer<void>();

  /// Waits until the journal has been loaded.
  Future<void> get ready => _readyCompleter.future;

  /// Runs the queued transfers and waits until no worker is busy.
  ///
  /// Used by the Android background worker: the foreground app is not there
  /// to drive the queue, so the worker drives it itself.
  Future<int> runPending() async {
    await ready;
    await _reload();
    while (_active.isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    // URI-backed folder items need the foreground Activity host for the
    // content-provider channel. They stay queued and are reported as done for
    // this background run so WorkManager does not spin on them.
    if (!_claimsForeground) {
      return _items.values
          .where((UploadItem item) =>
              item.state.isPending && item.sourceUri == null)
          .length;
    }
    return pendingCount;
  }

  /// Adds [source] to the queue for [folder].
  ///
  /// The same file is never queued twice while an earlier copy is still
  /// pending: a second "upload" of the same file would only make the server
  /// fight the first transfer over the same destination.
  Future<String> enqueue(UploadSource source, String folder) async {
    await ready;
    final destination = destinationFolder(folder, source.relativePath);
    final existing = _duplicateOf(source, destination);
    if (existing != null) return existing.id;

    final now = DateTime.now();
    final item = UploadItem(
      id: const Uuid().v4(),
      localPath: source.path,
      sourceUri: source.sourceUri,
      name: source.name,
      folder: destination,
      size: source.size,
      transferred: 0,
      state: UploadState.queued,
      error: null,
      attempts: 0,
      temporarySource: source.temporary,
      createdAt: now,
      updatedAt: now,
    );
    _items[item.id] = item;
    _waiting.add(item.id);
    await _persist(item);
    _notify();
    _pump();
    return item.id;
  }

  /// Adds many sources at once.
  ///
  /// The journal write is batched, so queueing a thousand files is one
  /// append pass rather than a thousand round trips.
  Future<List<String>> enqueueAll(
    Iterable<UploadSource> sources,
    String folder,
  ) async {
    await ready;
    final ids = <String>[];
    final added = <UploadItem>[];
    for (final source in sources) {
      final destination = destinationFolder(folder, source.relativePath);
      final existing = _duplicateOf(source, destination);
      if (existing != null) {
        ids.add(existing.id);
        continue;
      }
      final now = DateTime.now();
      final item = UploadItem(
        id: const Uuid().v4(),
        localPath: source.path,
        sourceUri: source.sourceUri,
        name: source.name,
        folder: destination,
        size: source.size,
        transferred: 0,
        state: UploadState.queued,
        error: null,
        attempts: 0,
        temporarySource: source.temporary,
        createdAt: now,
        updatedAt: now,
      );
      _items[item.id] = item;
      _waiting.add(item.id);
      added.add(item);
      ids.add(item.id);
    }
    if (added.isNotEmpty) {
      await _store.appendAll(added);
      for (final item in added) {
        _lastPersisted[item.id] = DateTime.now();
      }
    }
    _notify();
    _pump();
    return ids;
  }

  /// The destination folder of a file inside [folder].
  ///
  /// [relative] is the path of the file inside the folder it was picked from.
  /// Its directory is appended to [folder] so the nested structure survives
  /// the upload.
  static String destinationFolder(String folder, String relative) {
    final base = folder.trim();
    final tail = relative.trim();
    if (tail.isEmpty) return base;
    final directory =
        tail.contains('/') ? tail.substring(0, tail.lastIndexOf('/')) : '';
    if (directory.isEmpty) return base;
    final cleaned = directory
        .split('/')
        .where((String part) => part.isNotEmpty && part != '.')
        .join('/');
    if (cleaned.isEmpty) return base;
    return base.isEmpty ? cleaned : '$base/$cleaned';
  }

  /// The pending item that already covers [source], if any.
  UploadItem? _duplicateOf(UploadSource source, String folder) {
    for (final item in _items.values) {
      if (item.localPath != source.path) continue;
      if (item.folder != folder) continue;
      if (item.state == UploadState.completed) continue;
      if (item.state == UploadState.cancelled) continue;
      return item;
    }
    return null;
  }

  /// Holds a transfer back. The server session stays alive so it can resume.
  Future<void> pause(String id) async {
    final item = _items[id];
    if (item == null || item.state.isTerminal) return;
    _waiting.remove(id);
    final paused = item.copyWith(state: UploadState.paused);
    _items[id] = paused;
    await _persist(paused);
    _notify();
  }

  /// Releases a paused transfer.
  Future<void> resume(String id) async {
    final item = _items[id];
    if (item == null) return;
    if (item.state != UploadState.paused) return;
    final queued = item.copyWith(state: UploadState.queued, clearError: true);
    _items[id] = queued;
    if (!_waiting.contains(id)) _waiting.add(id);
    await _persist(queued);
    _notify();
    _pump();
  }

  /// Cancels a transfer and releases the server session.
  Future<void> cancel(String id) async {
    final item = _items[id];
    if (item == null || item.state == UploadState.completed) return;
    _cancelled.add(id);
    _waiting.remove(id);
    final cancelled = item.copyWith(
      state: UploadState.cancelled,
      clearError: true,
    );
    _items[id] = cancelled;
    await _persist(cancelled);
    _notify();
    // The server drops the staged bytes, so a cancelled transfer leaves
    // nothing behind on the disk.
    try {
      await _api?.cancelUpload(id);
    } catch (_) {
      // The server cleans up on its own once the session expires.
    }
    _deleteTemporarySource(cancelled);
  }

  /// Puts a failed transfer back in the queue.
  Future<void> retry(String id) async {
    final item = _items[id];
    if (item == null) return;
    if (item.state != UploadState.failed &&
        item.state != UploadState.cancelled) {
      return;
    }
    _cancelled.remove(id);
    final queued = item.copyWith(
      state: UploadState.queued,
      attempts: 0,
      clearError: true,
    );
    _items[id] = queued;
    if (!_waiting.contains(id)) _waiting.add(id);
    await _persist(queued);
    _notify();
    _pump();
  }

  /// Puts transfers that were interrupted back in the queue.
  ///
  /// Used when the app comes back to the foreground: a transfer that was
  /// `uploading` or `retrying` when the app was killed has no worker left, so
  /// it is queued again and resumes from the offset the server reports.
  Future<int> requeueInterrupted() async {
    final stuck = _items.values
        .where((UploadItem item) =>
            // An item whose worker is alive in *this* process is not stuck.
            // Re-queueing it used to start a second worker for the same id,
            // so two chunk requests raced each other and the server answered
            // one of them with a unique-constraint 500.
            !_active.contains(item.id) &&
            (item.state == UploadState.uploading ||
                item.state == UploadState.retrying))
        .toList(growable: false);
    for (final item in stuck) {
      final queued = item.copyWith(state: UploadState.queued, clearError: true);
      _items[item.id] = queued;
      if (!_waiting.contains(item.id)) _waiting.add(item.id);
      await _persist(queued);
    }
    if (stuck.isNotEmpty) {
      _notify();
      _pump();
    }
    return stuck.length;
  }

  /// Puts every failed transfer back in the queue.
  Future<int> retryFailed() async {
    final failed = _items.values
        .where((UploadItem item) => item.state == UploadState.failed)
        .map((UploadItem item) => item.id)
        .toList(growable: false);
    for (final id in failed) {
      await retry(id);
    }
    return failed.length;
  }

  /// Drops a transfer from the queue.
  ///
  /// Completed uploads stay on the server (removing the row never deletes a
  /// user file). An unfinished transfer with a server session is cancelled
  /// best-effort so its staging file does not linger until it expires.
  Future<void> remove(String id) async {
    final item = _items[id];
    if (item == null) return;
    _waiting.remove(id);
    _items.remove(id);
    _lastPersisted.remove(id);
    final hasSession = item.transferred > 0 ||
        item.state == UploadState.uploading ||
        item.state == UploadState.retrying ||
        item.state == UploadState.failed;
    if (item.state != UploadState.completed && hasSession) {
      _cancelled.add(id);
      unawaited(_cancelRemote(_api, id));
    }
    await _store.remove(id);
    _notify();
    if (item.temporarySource) _deleteTemporarySource(item);
  }

  /// Drops every completed transfer from the queue.
  Future<void> clearCompleted() async {
    final done = _items.values
        .where((UploadItem item) => item.state == UploadState.completed)
        .toList(growable: false);
    for (final item in done) {
      _items.remove(item.id);
      await _store.remove(item.id);
      if (item.temporarySource) _deleteTemporarySource(item);
    }
    _notify();
  }

  /// Pauses every transfer that is waiting or running.
  ///
  /// A running chunk is allowed to finish so the server's confirmed offset
  /// stays consistent; no further chunk is started for the item.
  Future<int> pauseAll() async {
    final paused = <UploadItem>[];
    for (final item in _items.values) {
      if (item.state != UploadState.queued &&
          item.state != UploadState.uploading &&
          item.state != UploadState.retrying) {
        continue;
      }
      _waiting.remove(item.id);
      final next = item.copyWith(state: UploadState.paused);
      _items[item.id] = next;
      paused.add(next);
    }
    if (paused.isNotEmpty) {
      await _persistAll(paused);
      _notify();
    }
    return paused.length;
  }

  /// Releases every paused transfer and restarts the queue.
  Future<int> resumeAll() async {
    final resumed = <UploadItem>[];
    for (final item in _items.values) {
      if (item.state != UploadState.paused) continue;
      final next = item.copyWith(state: UploadState.queued, clearError: true);
      _items[item.id] = next;
      if (!_waiting.contains(item.id)) _waiting.add(item.id);
      resumed.add(next);
    }
    if (resumed.isNotEmpty) {
      await _persistAll(resumed);
      _notify();
      _pump();
    }
    return resumed.length;
  }

  /// Removes every item from the queue.
  ///
  /// Active server sessions are cancelled (best effort) so their staging
  /// files are dropped instead of lingering until they expire. Completed
  /// uploads are already on the server, so removing their queue rows never
  /// deletes user files.
  Future<int> removeAll() async {
    if (_items.isEmpty) return 0;
    final removed = _items.values.toList(growable: false);
    _items.clear();
    _waiting.clear();
    for (final item in removed) {
      _lastPersisted.remove(item.id);
    }

    final api = _api;
    final cancelIds = <String>[];
    for (final item in removed) {
      // A queued item that never sent a byte has no server session, so a
      // thousand-item queue clear does not fire a thousand HTTP requests.
      final hasSession = item.transferred > 0 ||
          (item.state != UploadState.queued &&
              item.state != UploadState.cancelled);
      if (item.state != UploadState.completed && hasSession) {
        _cancelled.add(item.id);
        cancelIds.add(item.id);
      }
      if (item.temporarySource) _deleteTemporarySource(item);
    }
    unawaited(_cancelRemoteBatch(api, cancelIds));

    try {
      await _store.clear();
    } catch (_) {
      // The in-memory queue is already empty; a journal rewrite failure must
      // not make the UI disagree with what the user just did.
    }
    _notify();
    return removed.length;
  }

  Future<void> _cancelRemoteBatch(Api? api, List<String> ids) async {
    if (ids.isEmpty) return;
    var next = 0;
    Future<void> worker() async {
      while (next < ids.length) {
        final id = ids[next++];
        await _cancelRemote(api, id);
      }
    }

    await Future.wait(
      List<Future<void>>.generate(
        min(4, ids.length),
        (_) => worker(),
      ),
    );
  }

  Future<void> _cancelRemote(Api? api, String id) async {
    try {
      await api?.cancelUpload(id);
    } catch (_) {
      // The server drops stale sessions on its own.
    } finally {
      _cancelled.remove(id);
    }
  }

  /// Runs one transfer to completion.
  Future<void> _run(String id) async {
    final item = _items[id];
    if (item == null) return;
    final api = _api;
    if (api == null) return;

    if (item.state != UploadState.queued) return;
    final started = item.copyWith(
      state: UploadState.uploading,
      attempts: 0,
      clearError: true,
    );
    _items[id] = started;
    await _persist(started);
    _notify();

    try {
      await _transfer(api, started);
    } catch (error) {
      final current = _items[id];
      if (current == null) return;
      if (current.state == UploadState.cancelled) return;
      final failed = current.copyWith(
        state: UploadState.failed,
        error: _describe(error),
      );
      _items[id] = failed;
      await _persist(failed);
      _notify();
    }
  }

  /// The body of one transfer: reconcile with the server, then stream.
  Future<void> _transfer(Api api, UploadItem item) async {
    final id = item.id;

    if (item.size == 0) {
      await api.uploadChunk(
        uploadId: id,
        folder: item.folder,
        name: item.name,
        offset: 0,
        total: 0,
        bytes: const Stream<List<int>>.empty(),
        contentLength: 0,
      );
      await _complete(id);
      return;
    }

    // The server owns the offset. A brand-new item, or one whose journal
    // never recorded progress, starts at zero without paying for a status
    // round trip; if the server actually has more, its offset_mismatch reply
    // puts us back on the right byte.
    var offset = item.transferred > 0 ? await _serverOffset(api, id) : 0;
    if (offset < 0 || offset > item.size) offset = 0;

    var attempts = 0;
    while (offset < item.size) {
      if (_cancelled.contains(id)) {
        _cancelled.remove(id);
        return;
      }
      final current = _items[id];
      if (current == null || current.state == UploadState.paused) return;

      final end = min(offset + chunkSize, item.size);
      try {
        final result = await api.uploadChunk(
          uploadId: id,
          folder: item.folder,
          name: item.name,
          offset: offset,
          total: item.size,
          bytes: _chunkStream(item, offset, end),
          contentLength: end - offset,
          onProgress: (sent) => unawaited(_progress(id, offset + sent)),
        );
        final confirmed = (result['offset'] as num?)?.toInt() ?? end;
        offset = confirmed < 0 ? end : confirmed;
        attempts = 0;
        await _progress(id, offset);
        if (result['status'] == 'completed') {
          await _complete(id);
          return;
        }
      } on ApiException catch (error) {
        if (error.code == 'offset_mismatch') {
          // The server is at a different offset. Trust it and continue there.
          offset = await _serverOffset(api, id);
          if (offset < 0 || offset > item.size) offset = 0;
          continue;
        }
        if (!isTransient(error) || attempts >= maxAttempts) rethrow;
        await _backoff(id, attempts);
        attempts++;
      } catch (error) {
        if (!isTransient(error) || attempts >= maxAttempts) rethrow;
        await _backoff(id, attempts);
        attempts++;
      }
    }

    await _complete(id);
  }

  /// The offset the server has confirmed for [id].
  Future<int> _serverOffset(Api api, String id) async {
    try {
      final status = await api.uploadStatus(id);
      final raw = status['bytes_received'];
      return (raw as num?)?.toInt() ?? 0;
    } catch (error) {
      if (!isTransient(error)) return 0;
      rethrow;
    }
  }

  /// Waits before the next attempt and marks the item as retrying.
  Future<void> _backoff(String id, int attempt) async {
    final current = _items[id];
    if (current == null) return;
    final retrying = current.copyWith(state: UploadState.retrying);
    _items[id] = retrying;
    await _persist(retrying);
    _notify();
    final index = min(max(attempt, 0), backoffSeconds.length - 1);
    await Future<void>.delayed(Duration(seconds: backoffSeconds[index]));
  }

  /// Records the confirmed byte count.
  ///
  /// The write is throttled: the server holds the authoritative offset, so
  /// the persisted value is only a hint for the UI and for the next run.
  Future<void> _progress(String id, int transferred) async {
    final current = _items[id];
    if (current == null) return;
    if (current.transferred == transferred) return;
    final updated = current.copyWith(transferred: transferred);
    _items[id] = updated;
    final last = _lastPersisted[id];
    final now = DateTime.now();
    if (last == null || now.difference(last) >= progressInterval) {
      _lastPersisted[id] = now;
      await _persist(updated);
    }
    _notify();
  }

  /// Marks a transfer as stored.
  Future<void> _complete(String id) async {
    final current = _items[id];
    if (current == null) return;
    final done = current.copyWith(
      state: UploadState.completed,
      transferred: current.size,
      clearError: true,
      attempts: 0,
    );
    _items[id] = done;
    await _persist(done);
    _notify();
    if (done.temporarySource) _deleteTemporarySource(done);
  }

  Stream<List<int>> _chunkStream(UploadItem item, int start, int end) {
    final sourceUri = item.sourceUri;
    if (sourceUri != null) {
      return _contentChunkStream(sourceUri, start, end);
    }
    final file = File(item.localPath);
    if (!file.existsSync()) {
      throw const FileSystemException('The local file is no longer available');
    }
    return file.openRead(start, end);
  }

  /// Streams a chunk straight from an Android document URI.
  ///
  /// Each HTTP chunk is one provider read. Nothing is written to the cache:
  /// the only copy outside the original document is the transient chunk the
  /// HTTP client is sending.
  Stream<List<int>> _contentChunkStream(String uri, int start, int end) async* {
    // Read in small slices so each platform-channel message stays cheap; the
    // provider stream is still only read, never copied to app storage.
    var position = start;
    while (position < end) {
      final length = min(ContentSource.maxRange, end - position);
      final bytes = await ContentSource.readRange(uri, position, length);
      if (bytes.length != length) {
        throw const FileSystemException(
          'The document ended before the requested byte range',
        );
      }
      position += length;
      yield bytes;
    }
  }

  /// Removes a temporary source the app owns.
  void _deleteTemporarySource(UploadItem item) {
    if (!item.temporarySource) return;
    try {
      final file = File(item.localPath);
      if (file.existsSync()) file.deleteSync();
      _removeEmptyOwnedParents(file.path);
    } catch (_) {
      // A leftover temporary file is not worth failing an upload over.
    }
  }

  /// The `nexadrive-uploads` directory that owns [filePath], if any.
  ///
  /// Legacy folder picks copied a tree under
  /// `<cache>/nexadrive-uploads/<timestamp>/`. Only directories inside that
  /// marker are ever removed here, so this can never delete a user file.
  static Directory? _ownedUploadBase(String filePath) {
    var dir = File(filePath).parent;
    while (true) {
      final parent = dir.parent;
      if (parent.path == dir.path) return null;
      if (dir.path.split(Platform.pathSeparator).last == 'nexadrive-uploads') {
        return dir;
      }
      dir = parent;
    }
  }

  /// Deletes now-empty directories below the folder-upload cache root.
  static void _removeEmptyOwnedParents(String filePath) {
    final base = _ownedUploadBase(filePath);
    if (base == null) return;
    var dir = File(filePath).parent;
    while (dir.path != base.path && dir.path.startsWith(base.path)) {
      try {
        if (dir.listSync(followLinks: false).isNotEmpty) return;
        dir.deleteSync();
      } catch (_) {
        return;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) return;
      dir = parent;
    }
  }

  /// Removes legacy folder-upload copies that the journal no longer
  /// references.
  ///
  /// A cancelled picker, a crash during enqueue, or an old app version can
  /// leave multi-gigabyte folder copies in the cache. Only directories below
  /// `<temp>/nexadrive-uploads` that are older than [_orphanSourceAge] and are
  /// not named by a queued item are eligible, so an upload that is still
  /// resumable is never touched.
  static const Duration _orphanSourceAge = Duration(minutes: 30);

  Future<void> _cleanupOwnedFolderCache() async {
    try {
      final temp = await getTemporaryDirectory();
      final base = Directory(
        '${temp.path}${Platform.pathSeparator}nexadrive-uploads',
      );
      if (!await base.exists()) return;

      final referenced = <String>{};
      for (final item in _items.values) {
        if (!item.temporarySource) continue;
        final owner = _ownedUploadBase(item.localPath);
        if (owner != null) referenced.add(owner.path);
      }

      final now = DateTime.now();
      await for (final entity in base.list(followLinks: false)) {
        if (entity is! Directory) continue;
        if (referenced.contains(entity.path)) continue;
        try {
          final modified = (await entity.stat()).modified;
          if (now.difference(modified) < _orphanSourceAge) continue;
          await entity.delete(recursive: true);
        } catch (_) {
          // A directory that vanished or is busy next time is harmless.
        }
      }
    } catch (_) {
      // Cleanup is best-effort; it must never block the queue from loading.
    }
  }

  /// Starts workers for as many queued transfers as the pool allows.
  void _pump() {
    while (_active.length < concurrency) {
      final id = _takeNext();
      if (id == null) return;
      _active.add(id);
      unawaited(_run(id).whenComplete(() {
        _active.remove(id);
        _pump();
        _notify();
      }));
    }
  }

  /// The next queued transfer, skipping the ones that are not runnable.
  String? _takeNext() {
    while (_waiting.isNotEmpty) {
      final id = _waiting.removeAt(0);
      final item = _items[id];
      if (item == null) continue;
      if (item.state != UploadState.queued) continue;
      // A background isolate has no Activity host for the content-provider
      // channel. Leave URI-backed items for the next foreground run instead
      // of failing them or copying their bytes into the cache.
      if (!_claimsForeground && item.sourceUri != null) continue;
      if (_cancelled.contains(id)) continue;
      // A worker already owns this id. This can happen if a foreground resume
      // queued the item while its original chunk request was still in flight.
      if (_active.contains(id)) continue;
      return id;
    }
    return null;
  }

  /// Writes a batch of state changes as one journal append.
  Future<void> _persistAll(List<UploadItem> items) async {
    if (items.isEmpty) return;
    try {
      await _store.appendAll(items);
      final now = DateTime.now();
      for (final item in items) {
        _lastPersisted[item.id] = now;
      }
    } catch (_) {
      // A journal write must never abort an operation the user requested.
    }
  }

  /// Writes the item to the journal.
  Future<void> _persist(UploadItem item) async {
    try {
      await _store.append(item);
      _lastPersisted[item.id] = DateTime.now();
    } catch (_) {
      // A journal write must never abort a transfer that is already running.
    }
  }

  /// Coalesces notifications so a burst of progress ticks does not rebuild
  /// the tree once per byte.
  Timer? _notifyTimer;

  void _notify() {
    if (_notifyTimer != null) return;
    _notifyTimer = Timer(const Duration(milliseconds: 120), () {
      _notifyTimer = null;
      if (!_disposed) notifyListeners();
    });
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _notifyTimer?.cancel();
    _notifyTimer = null;
    _ownerTimer?.cancel();
    _ownerTimer = null;
    unawaited(_store.dispose());
    super.dispose();
  }

  /// Whether [error] is worth retrying instead of failing the transfer.
  ///
  /// Public so the sync engine can apply the same classification without
  /// duplicating the list of retryable status codes.
  static bool isTransient(Object error) {
    if (error is SocketException || error is TimeoutException) return true;
    if (error is http.ClientException) return true;
    if (error is ApiException) {
      const transient = <int>{408, 429, 500, 502, 503, 504};
      return transient.contains(error.status);
    }
    return false;
  }

  static String _describe(Object error) {
    if (error is ApiException) return error.message;
    return error.toString();
  }

  static String _journalPathFallback() {
    // Only used before the platform answers with a real support directory.
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return '$home/.nexadrive_upload_queue.jsonl';
  }

  /// The journal file the process uses.
  static Future<File> journalFile() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final folder = Directory('${directory.path}/uploads');
      if (!await folder.exists()) await folder.create(recursive: true);
      return File('${folder.path}/queue.jsonl');
    } catch (_) {
      return File(_journalPathFallback());
    }
  }

  /// The file that marks the foreground app as the owner of the queue.
  ///
  /// Only one process may transfer at a time. The foreground app refreshes
  /// this file while it is alive; the Android background worker checks it
  /// first and stays out of the way when the app is in front.
  static Future<File> ownerFile() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final folder = Directory('${directory.path}/uploads');
      if (!await folder.exists()) await folder.create(recursive: true);
      return File('${folder.path}/owner.lock');
    } catch (_) {
      return File('${_journalPathFallback()}.owner');
    }
  }

  /// How long an owner lock stays valid without a heartbeat.
  ///
  /// It is three times the heartbeat interval, so a background worker only
  /// takes over when the foreground app really is gone.
  static const Duration ownerLockTtl = Duration(seconds: 90);

  /// How often the foreground app refreshes its owner lock.
  static const Duration ownerHeartbeat = Duration(seconds: 30);

  Timer? _ownerTimer;
  File? _ownerFile;

  /// Claims the queue for this (foreground) process.
  void claimForeground() {
    if (!_claimsForeground) return;
    _ownerTimer?.cancel();
    _ownerTimer = Timer.periodic(ownerHeartbeat, (_) => _writeOwnerLock());
    unawaited(_writeOwnerLock());
  }

  /// Releases the claim so a background worker may take over.
  void releaseForeground() {
    _ownerTimer?.cancel();
    _ownerTimer = null;
    final file = _ownerFile;
    _ownerFile = null;
    if (file == null) return;
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // A stale lock expires on its own.
    }
  }

  Future<void> _writeOwnerLock() async {
    try {
      final file = await ownerFile();
      _ownerFile = file;
      await file.writeAsString(
        '${DateTime.now().toIso8601String()}\n$pid\n',
        flush: true,
      );
    } catch (_) {
      // Without a lock the queue still works; only the background worker
      // has to be more careful.
    }
  }

  /// Whether a live foreground app owns the queue right now.
  ///
  /// The background worker calls this before it touches the queue: two
  /// processes uploading the same file would only fight over the same
  /// destination.
  static Future<bool> isForegroundOwnerAlive() async {
    try {
      final file = await ownerFile();
      if (!await file.exists()) return false;
      final lines = await file.readAsLines();
      if (lines.isEmpty) return false;
      final stamp = DateTime.tryParse(lines.first.trim());
      if (stamp == null) return false;
      return DateTime.now().difference(stamp) < ownerLockTtl;
    } catch (_) {
      return false;
    }
  }
}
