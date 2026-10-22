import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'upload_item.dart';

/// File-backed journal of the upload queue.
///
/// The queue used to live in one SharedPreferences string that was decoded and
/// re-encoded on every single change. With a thousand files that is a
/// quadratic amount of work: enqueueing alone took about six seconds, and
/// every chunk wrote the whole list again.
///
/// This store is an append-only journal instead. A state change appends one
/// line, which is O(1) no matter how many files are queued, and the queue is
/// rebuilt by replaying the journal at startup. The journal is compacted
/// occasionally so it cannot grow without bound.
class UploadStore {
  UploadStore(this.file);

  /// The journal file.
  final File file;

  /// Number of journal lines after which the file is rewritten from the
  /// current state. Every line is a full snapshot of one item, so the
  /// journal grows with the number of *changes*, not the number of files.
  static const int compactAfterLines = 4000;

  /// Guards every write so two appends never interleave.
  Future<void> _lock = Future<void>.value();

  /// The open append handle. Reused so a progress tick does not pay for an
  /// open/close pair.
  RandomAccessFile? _handle;

  /// How many lines the journal currently holds.
  int _lines = 0;

  /// The newest snapshot of every item the journal knows about.
  final Map<String, UploadItem> _latest = <String, UploadItem>{};

  /// Reads the journal and returns the items it describes.
  ///
  /// Later lines win, so replaying is simply "apply every line in order".
  /// A truncated or corrupt line is skipped rather than failing the whole
  /// load: a half-written line must never cost the user the whole queue.
  Future<List<UploadItem>> load() async {
    _latest.clear();
    if (!await file.exists()) return <UploadItem>[];
    List<String> lines;
    try {
      lines = await file.readAsLines();
    } catch (_) {
      return <UploadItem>[];
    }
    _lines = lines.length;
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map) continue;
        final id = decoded['id'] as String?;
        if (id == null) continue;
        if (decoded['deleted'] == true) {
          _latest.remove(id);
          continue;
        }
        final raw = decoded['item'];
        if (raw is! Map) continue;
        _latest[id] = UploadItem.fromJson(Map<String, dynamic>.from(raw));
      } catch (_) {
        // Skip an unreadable line.
        continue;
      }
    }
    return _latest.values.toList(growable: false);
  }

  /// Appends a snapshot of [item].
  Future<void> append(UploadItem item) {
    _latest[item.id] = item;
    return _write(item.encode());
  }

  /// Appends snapshots of many items in one pass.
  ///
  /// Queueing a thousand files is a single append instead of a thousand
  /// round trips through the write lock.
  Future<void> appendAll(List<UploadItem> items) {
    if (items.isEmpty) return Future<void>.value();
    for (final item in items) {
      _latest[item.id] = item;
    }
    final buffer = StringBuffer();
    for (final item in items) {
      buffer.writeln(item.encode());
    }
    return _serialized(() async {
      final handle = await _openHandle();
      await handle.writeString(buffer.toString());
      _lines += items.length;
      if (_lines > compactAfterLines) {
        await _compactLocked(_latest.values.toList(growable: false));
      }
    });
  }

  /// Marks [id] as gone. The line stays in the journal until compaction.
  Future<void> remove(String id) {
    _latest.remove(id);
    return _write(jsonEncode({'id': id, 'deleted': true}));
  }

  /// Rewrites the journal so it holds exactly [items].
  Future<void> compact([List<UploadItem>? items]) {
    final snapshot = items ?? _latest.values.toList(growable: false);
    return _serialized(() => _compactLocked(snapshot));
  }

  /// Writes one journal line.
  Future<void> _write(String line) => _serialized(() async {
        final handle = await _openHandle();
        await handle.writeString('$line\n');
        _lines++;
        if (_lines > compactAfterLines) {
          // The journal grew past its budget: rewrite it from the current
          // state so the file cannot grow without bound.
          await _compactLocked(_latest.values.toList(growable: false));
        }
      });

  /// Rewrites the journal file. Must be called with the write lock held.
  Future<void> _compactLocked(List<UploadItem> snapshot) async {
    final buffer = StringBuffer();
    for (final item in snapshot) {
      buffer.writeln(item.encode());
    }
    await _closeHandle();
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(buffer.toString(), flush: true);
    await temp.rename(file.path);
    _lines = snapshot.length;
  }

  Future<void> _serialized(Future<void> Function() action) {
    final completer = Completer<void>();
    final previous = _lock;
    _lock = completer.future;
    previous.catchError((Object _) {}).whenComplete(() async {
      try {
        await action();
        completer.complete();
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  Future<RandomAccessFile> _openHandle() async {
    final existing = _handle;
    if (existing != null) return existing;
    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    final handle = await file.open(mode: FileMode.append);
    _handle = handle;
    return handle;
  }

  Future<void> _closeHandle() async {
    final handle = _handle;
    _handle = null;
    try {
      await handle?.close();
    } catch (_) {
      // Closing a handle that is already gone is not an error.
    }
  }

  /// Closes the journal handle. Safe to call more than once.
  Future<void> dispose() => _serialized(_closeHandle);
}
