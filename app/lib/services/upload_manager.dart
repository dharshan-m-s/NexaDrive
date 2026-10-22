import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'api.dart';
import 'upload_item.dart';
import 'upload_store.dart';

/// A local file that is ready to be uploaded.
///
/// The queue works with paths rather than picker objects so the same code
/// serves a desktop file, a materialised Android document and a test fixture.
class UploadSource {
  const UploadSource({
    required this.path,
    required this.name,
    required this.size,
    this.relativePath = '',
    this.temporary = false,
  });

  /// Absolute path of the file on this device.
  final String path;

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
    if (!manager._readyCompleter.isCompleted) manager._readyCompleter.complete();
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
  static const int chunkSize = 8 * 1024 * 1024;

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
  int get failedCount =>
      _items.values.where((UploadItem item) => item.state == UploadState.failed).length;

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
      if (item.state == UploadState.uploading ||
          item.state == UploadState.retrying) {
        final resumed = item.copyWith(
          state: UploadState.queued,
          clearError: true,
        );
        _items[item.id] = resumed;
        await _persist(resumed);
      }
      if (item.state == UploadState.queued) _waiting.add(item.id);
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
    final directory = tail.contains('/')
        ? tail.substring(0, tail.lastIndexOf('/'))
        : '';
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
    if (item.state != UploadState.failed && item.state != UploadState.cancelled) {
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
            item.state == UploadState.uploading ||
            item.state == UploadState.retrying)
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

  /// Drops a transfer from the queue without touching the server.
  Future<void> remove(String id) async {
    final item = _items[id];
    if (item == null) return;
    _waiting.remove(id);
    _items.remove(id);
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

    // The server owns the offset. Asking for it first means a resumed
    // transfer continues at the byte the server actually stored.
    var offset = await _serverOffset(api, id);
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
    final file = File(item.localPath);
    if (!file.existsSync()) {
      throw const FileSystemException('The local file is no longer available');
    }
    return file.openRead(start, end);
  }

  /// Removes a temporary source the app owns.
  void _deleteTemporarySource(UploadItem item) {
    if (!item.temporarySource) return;
    try {
      final file = File(item.localPath);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // A leftover temporary file is not worth failing an upload over.
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
      if (_cancelled.contains(id)) continue;
      return id;
    }
    return null;
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
