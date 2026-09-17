import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'api.dart';

class TransferItem {
  final String id;
  final String path;
  final String name;
  final String folder;
  final int size;
  final int transferred;
  final String status;
  final String? error;
  final DateTime createdAt;

  const TransferItem({required this.id, required this.path, required this.name, required this.folder, required this.size, required this.transferred, required this.status, required this.error, required this.createdAt});

  Map<String, dynamic> toJson() => {'id': id, 'path': path, 'name': name, 'folder': folder, 'size': size, 'transferred': transferred, 'status': status, 'error': error, 'createdAt': createdAt.toIso8601String()};
  factory TransferItem.fromJson(Map<String, dynamic> j) => TransferItem(id: j['id'], path: j['path'], name: j['name'], folder: j['folder'] ?? '', size: (j['size'] as num?)?.toInt() ?? 0, transferred: (j['transferred'] as num?)?.toInt() ?? 0, status: j['status'] ?? 'queued', error: j['error'], createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now());
  TransferItem copyWith({String? status, String? error, int? transferred}) => TransferItem(id: id, path: path, name: name, folder: folder, size: size, transferred: transferred ?? this.transferred, status: status ?? this.status, error: error, createdAt: createdAt);
}

class TransferQueue {
  static const _key = 'transfer_queue_v2';
  static const int chunkSize = 8 * 1024 * 1024;
  final Api api;
  final Set<String> _paused = <String>{};
  bool _processing = false;
  TransferQueue(this.api);

  Future<List<TransferItem>> items() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => TransferItem.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<void> _save(List<TransferItem> list) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  Future<TransferItem> enqueue(PlatformFile file, String folder) async {
    final path = file.path;
    if (path == null) throw Exception('The selected file is not readable');
    return enqueueLocalPath(path, name: file.name, folder: folder, size: file.lengthSync());
  }

  Future<TransferItem> enqueueLocalPath(String path, {required String name, required String folder, int? size}) async {
    final actualSize = size ?? await File(path).length();
    final id = const Uuid().v4();
    final item = TransferItem(id: id, path: path, name: name, folder: folder, size: actualSize, transferred: 0, status: 'queued', error: null, createdAt: DateTime.now());
    final list = await items();
    list.add(item);
    await _save(list);
    return item;
  }

  Future<void> remove(String id) async { final list = await items(); list.removeWhere((e) => e.id == id); _paused.remove(id); await _save(list); }
  Future<void> clearCompleted() async { final list = await items(); list.removeWhere((e) => e.status == 'completed'); await _save(list); }
  Future<void> pause(String id) async { _paused.add(id); }
  void resume(String id) { _paused.remove(id); }

  Future<void> reset(String id) async {
    final list = await items();
    final i = list.indexWhere((e) => e.id == id);
    if (i < 0) return;
    list[i] = list[i].copyWith(status: 'queued', error: null, transferred: 0);
    _paused.remove(id);
    await _save(list);
  }

  Stream<List<int>> _chunkStream(TransferItem item, int start, int end) {
    if (item.path.isNotEmpty) return File(item.path).openRead(start, end);
    throw Exception('The local source file is no longer available');
  }

  /// Automatic retry budget per item. Transient failures (network blips,
  /// 5xx responses) are retried in-process with growing backoff before the
  /// row is surfaced as needing attention — flaky Wi-Fi/mobile handoffs no
  /// longer fail an upload on the first hiccup.
  static const _maxRetries = 3;

  /// Backoff delays, in seconds, for retries 1.._maxRetries.
  static const _backoffSeconds = [2, 5, 10];

  /// Whether [e] is worth retrying in-process rather than surfacing as a
  /// permanent failure.
  static bool _isTransient(Object e) {
    if (e is SocketException || e is TimeoutException) return true;
    if (e is http.ClientException) return true;
    if (e is ApiException) {
      const transient = {408, 429, 500, 502, 503, 504};
      return transient.contains(e.status);
    }
    return false;
  }

  /// Uploads [item] end-to-end: reconcile against the server's recorded
  /// progress, stream the remaining chunks, and persist every change through
  /// [persist]. Transient failures retry in-place (resuming from the
  /// server-reported offset) with exponential backoff; anything that survives
  /// [TransferQueue._maxRetries] rethrows.
  Future<TransferItem> _uploadItem(
    TransferItem item, {
    required Future<void> Function(TransferItem) persist,
  }) async {
    var last = item;
    var retries = 0;

    while (true) {
      try {
        final remote = await api.uploadStatus(last.id);
        if (remote['status'] == 'completed') {
          final done =
              last.copyWith(status: 'completed', transferred: last.size, error: null);
          await persist(done);
          return done;
        }
        var offset = (remote['bytes_received'] as num?)?.toInt() ?? last.transferred;
        if (offset < 0 || offset > last.size) offset = 0;
        last = last.copyWith(status: 'uploading', transferred: offset, error: null);
        await persist(last);

        if (last.size == 0) {
          final result = await api.uploadChunk(
            uploadId: last.id,
            folder: last.folder,
            name: last.name,
            offset: 0,
            total: 0,
            bytes: const Stream<List<int>>.empty(),
            contentLength: 0,
          );
          final status = result['status'] == 'completed' ? 'completed' : 'uploading';
          last = last.copyWith(status: status, transferred: 0, error: null);
          await persist(last);
          if (status == 'completed') return last;
        }

        while (offset < last.size) {
          if (_paused.contains(last.id)) {
            last = last.copyWith(status: 'queued', transferred: offset, error: 'Paused');
            await persist(last);
            return last;
          }
          final end =
              (offset + chunkSize > last.size) ? last.size : offset + chunkSize;
          final result = await api.uploadChunk(
            uploadId: last.id,
            folder: last.folder,
            name: last.name,
            offset: offset,
            total: last.size,
            bytes: _chunkStream(last, offset, end),
            contentLength: end - offset,
          );
          offset = (result['offset'] as num?)?.toInt() ?? end;
          final status =
              result['status'] == 'completed' ? 'completed' : 'uploading';
          last = last.copyWith(status: status, transferred: offset, error: null);
          await persist(last);
          if (status == 'completed') return last;
        }

        if (last.status != 'completed') {
          last = last.copyWith(status: 'queued', error: null);
          await persist(last);
        }
        return last;
      } catch (e) {
        if (_paused.contains(last.id)) {
          last = last.copyWith(status: 'queued', error: 'Paused');
          await persist(last);
          return last;
        }
        if (!_isTransient(e) || retries >= _maxRetries) {
          rethrow;
        }
        final delay = Duration(seconds: _backoffSeconds[retries]);
        retries++;
        await Future<void>.delayed(delay);
      }
    }
  }

  Future<void> process({void Function(List<TransferItem>)? onChanged}) async {
    if (_processing) return;
    _processing = true;
    try {
      var list = await items();
      for (var i = 0; i < list.length; i++) {
        var item = list[i];
        if (item.status == 'completed') continue;
        if (_paused.contains(item.id)) continue;
        if (item.path.isEmpty) {
          list[i] = item.copyWith(status: 'queued', error: 'Local file path is unavailable');
          await _save(list); onChanged?.call(List.unmodifiable(list));
          continue;
        }

        Future<void> persist(TransferItem updated) async {
          list[i] = updated;
          await _save(list);
          onChanged?.call(List.unmodifiable(list));
        }

        try {
          final result = await _uploadItem(item, persist: persist);
          list[i] = result;
          await _save(list);
          onChanged?.call(List.unmodifiable(list));
        } catch (e) {
          // Automatic retries are exhausted. Keep the row queued with the
          // error attached so the Transfers screen can offer a manual retry,
          // and a later process() pass will pick it up automatically.
          list[i] = list[i].copyWith(status: 'queued', error: e.toString());
          await _save(list); onChanged?.call(List.unmodifiable(list));
        }
      }
    } finally {
      _processing = false;
    }
  }
}
