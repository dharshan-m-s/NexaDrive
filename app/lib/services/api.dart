import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'session.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);

  @override
  String toString() => message;
}

/// Wraps any [http.Client] so a single request cannot hang forever.
///
/// The wait for the response head (connection + headers) is capped for every
/// request; upload payloads get a much more generous bound so slow uplinks
/// still work. Large body reads are additionally capped at the call sites in
/// [Api] via [Api._transferTimeout].
class _TimedClient extends http.BaseClient {
  _TimedClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final contentLength = request.contentLength ?? 0;
    final timeout = contentLength > (1 << 20)
        ? Api._transferTimeout
        : Api._controlTimeout;
    return _inner.send(request).timeout(timeout);
  }

  @override
  void close() => _inner.close();
}

class Api {
  final Session session;
  final http.Client _client;

  /// Upper bound for control-plane requests (JSON list/metadata/actions).
  /// On a silent network failure these would otherwise wait forever.
  static const _controlTimeout = Duration(seconds: 30);

  /// Generous bound for full-body transfers and large upload header waits.
  static const _transferTimeout = Duration(minutes: 10);

  /// Invoked when an authenticated request returns HTTP 401 (expired or
  /// invalid session token). The UI wires this to clear the session and
  /// return to the login screen.
  Future<void> Function()? onUnauthorized;

  Api(this.session, {http.Client? client})
      : _client = _TimedClient(client ?? http.Client());

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = session.serverUrl;
    if (base == null) throw Exception('Server is not configured');
    final normalized = Session.normalizeServerUrl(base);
    return Uri.parse('$normalized$path').replace(queryParameters: query);
  }

  Map<String, String> get authHeaders => _headers;

  Map<String, String> get _headers => {
    'Authorization': 'Bearer ${session.token}',
  };

  Future<Map<String, dynamic>> login(
    String server,
    String username,
    String password,
  ) async {
    final base = Session.normalizeServerUrl(server);
    final response = await _client.post(
      Uri.parse('$base/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );

    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, _message(response));
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> listFiles(String path) async {
    final response = await _client.get(
      _uri('/api/files', {'path': path}),
      headers: _headers,
    );
    _check(response);
    return (jsonDecode(response.body) as List)
        .cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> storage() async {
    final response = await _client.get(
      _uri('/api/storage'),
      headers: _headers,
    );
    _check(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> createFolder(String path) async {
    final response = await _client.post(
      _uri('/api/folders'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'path': path}),
    );
    _check(response);
  }

  Future<Map<String, dynamic>> upload(
    PlatformFile file,
    String folder, {
    required String uploadId,
  }) async {
    if (file.path == null) {
      // Not on local disk (e.g. a web pick): read the bytes eagerly.
      final bytes = await file.readAsBytes();
      return uploadBytes(bytes, file.name, folder, uploadId: uploadId);
    }

    final request = http.MultipartRequest(
      'POST',
      _uri('/api/files/upload'),
    );
    request.headers.addAll(_headers);
    request.fields['path'] = folder;
    request.fields['upload_id'] = uploadId;

    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path!,
        filename: file.name,
      ),
    );

    final streamed = await _client.send(request).timeout(_transferTimeout);
    final response = await http.Response.fromStream(streamed).timeout(_controlTimeout);
    _check(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Upload path for content that is already in memory (generated PDFs,
  /// web picks without a local file).
  Future<Map<String, dynamic>> uploadBytes(
    Uint8List bytes,
    String name,
    String folder, {
    required String uploadId,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      _uri('/api/files/upload'),
    );
    request.headers.addAll(_headers);
    request.fields['path'] = folder;
    request.fields['upload_id'] = uploadId;
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: name),
    );

    final streamed = await _client.send(request).timeout(_transferTimeout);
    final response = await http.Response.fromStream(streamed).timeout(_controlTimeout);
    _check(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> uploadChunk({
    required String uploadId,
    required String folder,
    required String name,
    required int offset,
    required int total,
    required Stream<List<int>> bytes,
    required int contentLength,
  }) async {
    final request = http.StreamedRequest('POST', _uri('/api/uploads/chunk', {
      'upload_id': uploadId,
      'path': folder,
      'name': name,
      'offset': '$offset',
      'total': '$total',
    }));
    request.headers.addAll({..._headers, 'Content-Length': '$contentLength'});
    request.contentLength = contentLength;
    final responseFuture = _client.send(request).timeout(_transferTimeout);
    try {
      await request.sink.addStream(bytes);
      await request.sink.close();
    } catch (e) {
      unawaited(responseFuture.then<void>((_) {}, onError: (_) {}));
      rethrow;
    }
    final response = await http.Response.fromStream(await responseFuture);
    _check(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Uri fileDownloadUri(String path) => _uri('/api/files/download', {'path': path});

  /// Fetches a server-generated JPEG thumbnail. Throws [ApiException] with
  /// status 415 when the server can't generate one (e.g. HEIC without a
  /// codec) so callers can fall back to a full download.
  Future<Uint8List> thumbnail(String path, {int max = 512}) async {
    final response = await _client.get(
      _uri('/api/files/thumbnail', {'path': path, 'max': '$max'}),
      headers: _headers,
    );
    if (response.statusCode == 415 || response.statusCode == 400) {
      throw ApiException(415, 'Thumbnail not available');
    }
    _check(response);
    return response.bodyBytes;
  }

  Future<Uint8List> download(String path) async {
    final response = await _client
        .get(
          _uri('/api/files/download', {'path': path}),
          headers: _headers,
        )
        .timeout(_transferTimeout);
    _check(response);
    return response.bodyBytes;
  }

  Future<void> downloadToFile(String path, String targetPath) async {
    final request = http.Request('GET', _uri('/api/files/download', {'path': path}));
    request.headers.addAll(_headers);
    final response = await _client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw ApiException(response.statusCode, _messageFromBody(body, response.statusCode));
    }
    final tempPath = '$targetPath.nexadrive-download-${DateTime.now().microsecondsSinceEpoch}.tmp';
    final temp = File(tempPath);
    final destination = File(targetPath);
    final sink = temp.openWrite();
    var sinkClosed = false;
    try {
      await response.stream.pipe(sink).timeout(_transferTimeout);
      await sink.flush();
      await sink.close();
      sinkClosed = true;
      if (await destination.exists()) await destination.delete();
      await temp.rename(targetPath);
    } finally {
      if (!sinkClosed) await sink.close();
      try { await temp.delete(); } catch (_) {}
    }
  }


  Future<Map<String, dynamic>> serverStatus() async {
    final response = await _client.get(_uri('/api/server/status'));
    _check(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> uploadStatus(String uploadId) async {
    final response = await _client.get(_uri('/api/uploads/status', {'upload_id': uploadId}), headers: _headers);
    _check(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> photos() async {
    final response = await _client.get(_uri('/api/photos'), headers: _headers);
    _check(response);
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }
  Future<void> delete(String path) async {
    final response = await _client.delete(
      _uri('/api/files', {'path': path}),
      headers: _headers,
    );
    _check(response);
  }

  Future<List<Map<String, dynamic>>> trash() async {
    final response = await _client.get(_uri('/api/trash'), headers: _headers);
    _check(response);
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  Future<void> restoreTrash(String id) async {
    final response = await _client.post(
      _uri('/api/trash/restore', {'id': id}),
      headers: _headers,
    );
    _check(response);
  }

  Future<void> permanentlyDeleteTrash(String id) async {
    final response = await _client.delete(
      _uri('/api/trash', {'id': id}),
      headers: _headers,
    );
    _check(response);
  }


  Future<List<Map<String, dynamic>>> searchFiles(String query) async {
    final response = await _client.get(
      _uri('/api/files/search', {'q': query}),
      headers: _headers,
    );
    _check(response);
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  Future<String> rename(String source, String name) async {
    final response = await _client.post(
      _uri('/api/files/rename'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'source': source, 'name': name}),
    );
    _check(response);
    return (jsonDecode(response.body) as Map<String, dynamic>)['path'] as String;
  }

  Future<String> move(String source, String destination) async {
    final response = await _client.post(
      _uri('/api/files/move'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'source': source, 'destination': destination}),
    );
    _check(response);
    return (jsonDecode(response.body) as Map<String, dynamic>)['path'] as String;
  }

  Future<String> copy(String source, String destination) async {
    final response = await _client.post(
      _uri('/api/files/copy'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'source': source, 'destination': destination}),
    );
    _check(response);
    return (jsonDecode(response.body) as Map<String, dynamic>)['path'] as String;
  }

  Future<List<String>> batch({
    required String action,
    required List<String> paths,
    String? destination,
  }) async {
    final response = await _client.post(
      _uri('/api/files/batch'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': action,
        'paths': paths,
        if (destination != null) 'destination': destination,
      }),
    );
    _check(response);
    return (jsonDecode(response.body) as List).cast<String>();
  }
  Future<List<Map<String, dynamic>>> users() async {
    final response = await _client.get(_uri('/api/admin/users'), headers: _headers);
    _check(response);
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createUser({required String username, required String displayName, required String password, String role = 'user', int? quotaBytes}) async {
    final response = await _client.post(_uri('/api/admin/users'), headers: {..._headers, 'Content-Type': 'application/json'}, body: jsonEncode({'username': username, 'display_name': displayName, 'password': password, 'role': role, if (quotaBytes != null) 'quota_bytes': quotaBytes}));
    _check(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> updateUser(String id, {String? displayName, String? role, bool? disabled, int? quotaBytes, String? password}) async {
    final response = await _client.put(_uri('/api/admin/users/$id'), headers: {..._headers, 'Content-Type': 'application/json'}, body: jsonEncode({if (displayName != null) 'display_name': displayName, if (role != null) 'role': role, if (disabled != null) 'disabled': disabled, if (quotaBytes != null) 'quota_bytes': quotaBytes, if (password != null && password.isNotEmpty) 'password': password}));
    _check(response);
  }

  Future<void> deleteUser(String id) async {
    final response = await _client.delete(_uri('/api/admin/users/$id'), headers: _headers);
    _check(response);
  }

  Future<List<Map<String, dynamic>>> audit({int limit = 200}) async {
    final response = await _client.get(_uri('/api/admin/audit', {'limit': limit.toString()}), headers: _headers);
    _check(response);
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> shares() async {
    final response = await _client.get(_uri('/api/shares'), headers: _headers);
    _check(response);
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createShare({required String path, String? username, required String permission, DateTime? expiresAt}) async {
    final response = await _client.post(_uri('/api/shares'), headers: {..._headers, 'Content-Type': 'application/json'}, body: jsonEncode({'path': path, if (username != null && username.isNotEmpty) 'username': username, 'permission': permission, if (expiresAt != null) 'expires_at': expiresAt.toUtc().toIso8601String()}));
    _check(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> deleteShare(String id) async {
    final response = await _client.delete(_uri('/api/shares', {'id': id}), headers: _headers);
    _check(response);
  }

  Future<List<Map<String, dynamic>>> shared() async {
    final response = await _client.get(_uri('/api/shared'), headers: _headers);
    _check(response);
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> sharedItems(String shareId, String path) async {
    final response = await _client.get(_uri('/api/shared/items', {'share_id': shareId, if (path.isNotEmpty) 'path': path}), headers: _headers);
    _check(response);
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  Future<void> sharedAction({required String shareId, required String action, required String path, String? name, String? destination}) async {
    final response = await _client.post(_uri('/api/shared/action'), headers: {..._headers, 'Content-Type': 'application/json'}, body: jsonEncode({'share_id': shareId, 'action': action, 'path': path, if (name != null) 'name': name, if (destination != null) 'destination': destination}));
    _check(response);
  }

  Future<Map<String, dynamic>> syncManifest({String? deviceId, String? deviceName}) async {
    final response = await _client.get(
      _uri('/api/sync/manifest', {if (deviceId != null) 'device_id': deviceId, if (deviceName != null) 'device_name': deviceName}),
      headers: _headers,
    );
    _check(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> syncDelta({required String since, String? deviceId, String? deviceName}) async {
    final response = await _client.get(
      _uri('/api/sync/delta', {
        'since': since,
        if (deviceId != null) 'device_id': deviceId,
        if (deviceName != null) 'device_name': deviceName,
      }),
      headers: _headers,
    );
    _check(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> syncDevices() async {
    final response = await _client.get(_uri('/api/sync/devices'), headers: _headers);
    _check(response);
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  Future<void> revokeSyncDevice(String id) async {
    final response = await _client.delete(_uri('/api/sync/devices', {'id': id}), headers: _headers);
    _check(response);
  }

  Future<List<Map<String, dynamic>>> notifications({bool unreadOnly = false}) async {
    final response = await _client.get(_uri('/api/notifications', {'unread': unreadOnly ? 'true' : 'false'}), headers: _headers);
    _check(response);
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  Future<void> markNotificationRead(String id) async {
    final response = await _client.post(_uri('/api/notifications/read'), headers: {..._headers, 'Content-Type': 'application/json'}, body: jsonEncode({'id': id}));
    _check(response);
  }

  Future<void> markAllNotificationsRead() async {
    final response = await _client.post(_uri('/api/notifications/read'), headers: {..._headers, 'Content-Type': 'application/json'}, body: jsonEncode({'all': true}));
    _check(response);
  }

  Future<List<Map<String, dynamic>>> backupSnapshots() async {
    final response = await _client.get(_uri('/api/backup/snapshots'), headers: _headers);
    _check(response);
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> restoreBackup(String snapshotId) async {
    final response = await _client.post(_uri('/api/backup/restore'), headers: {..._headers, 'Content-Type': 'application/json'}, body: jsonEncode({'snapshot_id': snapshotId}));
    _check(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> syncDelete(String path) async {
    final response = await _client.post(
      _uri('/api/sync/delete'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'path': path}),
    );
    _check(response);
  }

  Future<Map<String, dynamic>> backupStatus() async {
    final response = await _client.get(_uri('/api/backup/status'), headers: _headers);
    _check(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> runBackup({bool prune = false}) async {
    final response = await _client.post(
      _uri('/api/backup/run'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'prune': prune}),
    );
    _check(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> checkBackup() async {
    final response = await _client.post(_uri('/api/backup/check'), headers: _headers);
    _check(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> logout() async {
    if (session.token != null) {
      await _client.post(
        _uri('/api/auth/logout'),
        headers: _headers,
      );
    }
    await session.clear();
  }

  void _check(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401) {
        // Let the UI know the session is no longer valid so it can redirect
        // back to the login screen instead of showing a transient error.
        final handler = onUnauthorized;
        if (handler != null) {
          // Fire-and-forget; the handler is responsible for error handling
          // and only acts when it is mounted.
          unawaited(handler());
        }
      }
      throw ApiException(response.statusCode, _message(response));
    }
  }

  String _messageFromBody(String body, int status) {
    try {
      return (jsonDecode(body) as Map)['error']?.toString() ?? 'Request failed';
    } catch (_) {
      return 'Request failed ($status)';
    }
  }

  String _message(http.Response response) {
    try {
      return (jsonDecode(response.body) as Map)['error']?.toString()
          ?? 'Request failed';
    } catch (_) {
      return 'Request failed (${response.statusCode})';
    }
  }
}