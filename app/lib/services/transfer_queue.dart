import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
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

        try {
          final remote = await api.uploadStatus(item.id);
          if (remote['status'] == 'completed') {
            item = item.copyWith(status: 'completed', transferred: item.size, error: null);
            list[i] = item; await _save(list); onChanged?.call(List.unmodifiable(list)); continue;
          }
          var offset = (remote['bytes_received'] as num?)?.toInt() ?? item.transferred;
          if (offset < 0 || offset > item.size) offset = 0;
          item = item.copyWith(status: 'uploading', transferred: offset, error: null);
          list[i] = item; await _save(list); onChanged?.call(List.unmodifiable(list));

          if (item.size == 0) {
            final result = await api.uploadChunk(uploadId: item.id, folder: item.folder, name: item.name, offset: 0, total: 0, bytes: const Stream<List<int>>.empty(), contentLength: 0);
            item = item.copyWith(status: result['status'] == 'completed' ? 'completed' : 'queued', transferred: 0, error: null);
            list[i] = item; await _save(list); onChanged?.call(List.unmodifiable(list));
          }

          while (offset < item.size) {
            if (_paused.contains(item.id)) {
              item = item.copyWith(status: 'queued', transferred: offset, error: 'Paused');
              list[i] = item; await _save(list); onChanged?.call(List.unmodifiable(list));
              break;
            }
            final end = (offset + chunkSize > item.size) ? item.size : offset + chunkSize;
            final result = await api.uploadChunk(
              uploadId: item.id,
              folder: item.folder,
              name: item.name,
              offset: offset,
              total: item.size,
              bytes: _chunkStream(item, offset, end),
              contentLength: end - offset,
            );
            offset = (result['offset'] as num?)?.toInt() ?? end;
            item = item.copyWith(status: result['status'] == 'completed' ? 'completed' : 'uploading', transferred: offset, error: null);
            list[i] = item; await _save(list); onChanged?.call(List.unmodifiable(list));
          }
        } catch (e) {
          list[i] = item.copyWith(status: 'queued', transferred: item.transferred, error: e.toString());
          await _save(list); onChanged?.call(List.unmodifiable(list));
        }
      }
    } finally {
      _processing = false;
    }
  }
}
