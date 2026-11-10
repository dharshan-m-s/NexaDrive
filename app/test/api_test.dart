import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexadrive/services/api.dart';
import 'package:nexadrive/services/session.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ImmediateResponseClient extends http.BaseClient {
  _ImmediateResponseClient(this.response);

  final http.Response response;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    // Consume the request body independently from the early response, as a
    // server can reject a chunk before the client finishes streaming it.
    request.finalize().listen((_) {}, onError: (Object _) {});
    return Future<http.StreamedResponse>.value(
      http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode(response.body)),
        response.statusCode,
        headers: response.headers,
      ),
    );
  }
}

void setUpStorage() {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  FlutterSecureStorage.setMockInitialValues(<String, String>{});
}

Future<Session> loadSession({String? token}) async {
  final session = Session();
  await session.load();
  return session;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Server URL normalization', () {
    test('strips a single trailing slash', () {
      expect(Session.normalizeServerUrl('https://server.com/'),
          'https://server.com');
    });

    test('strips multiple trailing slashes', () {
      expect(Session.normalizeServerUrl('https://server.com//'),
          'https://server.com');
      expect(Session.normalizeServerUrl('https://server.com///'),
          'https://server.com');
    });

    test('strips surrounding whitespace', () {
      expect(Session.normalizeServerUrl('  https://server.com/  '),
          'https://server.com');
    });

    test('leaves a clean URL unchanged', () {
      expect(Session.normalizeServerUrl('https://server.com'),
          'https://server.com');
    });

    test('assumes https:// when no scheme is given', () {
      expect(
          Session.normalizeServerUrl('nas.lan:8080'), 'https://nas.lan:8080');
    });

    test('preserves an explicit http:// scheme', () {
      expect(Session.normalizeServerUrl('http://192.168.1.100:8080'),
          'http://192.168.1.100:8080');
    });
  });

  group('Login request construction', () {
    setUp(setUpStorage);

    test('posts to the login endpoint with a JSON body and parses the token',
        () async {
      final session = await loadSession();
      late Uri capturedUri;
      late Map<String, String> capturedHeaders;
      late String capturedBody;

      final client = MockClient((request) async {
        capturedUri = request.url;
        capturedHeaders = request.headers;
        capturedBody = request.body;
        return http.Response(
          jsonEncode({
            'token': 'abc123token',
            'user': {
              'id': '11111111-1111-1111-1111-111111111111',
              'username': 'alice',
              'display_name': 'Alice',
              'role': 'admin',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = Api(session, client: client);
      final result = await api.login(
          'https://server.example.com', 'alice', 'test-pass-123');

      expect(
          capturedUri.toString(), 'https://server.example.com/api/auth/login');
      expect(capturedHeaders['Content-Type'], 'application/json');
      final sent = jsonDecode(capturedBody) as Map<String, dynamic>;
      expect(sent['username'], 'alice');
      expect(sent['password'], 'test-pass-123');
      // The client reports its platform (and a device label when the OS
      // exposes a meaningful one) so the session list can name devices.
      expect(sent['platform'], isNotEmpty);
      expect(result['token'], 'abc123token');
      expect((result['user'] as Map)['username'], 'alice');
    });

    test('normalizes trailing slashes in the login URL', () async {
      final session = await loadSession();
      late Uri capturedUri;
      final client = MockClient((request) async {
        capturedUri = request.url;
        return http.Response(
            jsonEncode({
              'token': 't',
              'user': {
                'id': '11111111-1111-1111-1111-111111111111',
                'username': 'bob',
                'display_name': 'Bob',
                'role': 'user',
              },
            }),
            200);
      });

      final api = Api(session, client: client);
      await api.login('https://server.com//', 'bob', 'password123');

      expect(capturedUri.toString(), 'https://server.com/api/auth/login');
    });

    test('throws ApiException with the server error message on failure',
        () async {
      final session = await loadSession();
      final client = MockClient((request) async {
        return http.Response(jsonEncode({'error': 'Unauthorized'}), 401);
      });

      final api = Api(session, client: client);
      expect(
        () => api.login('https://server.com', 'alice', 'wrong'),
        throwsA(isA<ApiException>()
            .having((e) => e.status, 'status', 401)
            .having((e) => e.message, 'message', 'Unauthorized')),
      );
    });
  });

  group('Authenticated request behavior', () {
    setUp(() async {
      setUpStorage();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('server_url', 'https://server.com');
      FlutterSecureStorage.setMockInitialValues(
          <String, String>{'token': 'secret-token'});
    });

    test('attaches the Bearer token to authenticated requests', () async {
      final session = await loadSession();
      expect(session.token, 'secret-token');
      expect(session.serverUrl, 'https://server.com');

      late Map<String, String> capturedHeaders;
      final client = MockClient((request) async {
        capturedHeaders = request.headers;
        return http.Response(jsonEncode(<Object>[]), 200);
      });

      final api = Api(session, client: client);
      await api.listFiles('');

      expect(capturedHeaders['Authorization'], 'Bearer secret-token');
    });

    test('does not produce a double slash in the authenticated URL', () async {
      // Simulate a stored server URL with trailing slashes.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('server_url', 'https://server.com//');

      final session = await loadSession();
      late Uri capturedUri;
      final client = MockClient((request) async {
        capturedUri = request.url;
        return http.Response(jsonEncode(<Object>[]), 200);
      });

      final api = Api(session, client: client);
      await api.listFiles('');

      final url = capturedUri.toString();
      expect(url, startsWith('https://server.com/api/files'));
      expect(url.contains('server.com//'), isFalse);
    });
  });

  group('Shared access API', () {
    setUp(() async {
      setUpStorage();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('server_url', 'https://server.com');
      FlutterSecureStorage.setMockInitialValues(
        <String, String>{'token': 'secret-token'},
      );
    });

    test('preserves received owner and sent-share expiry response fields',
        () async {
      final session = await loadSession();
      final client = MockClient((request) async {
        if (request.url.path == '/api/shared') {
          return http.Response(
            jsonEncode([
              {
                'id': 'received-1',
                'name': 'Project',
                'path': 'Project',
                'permission': 'write',
                'owner': 'alice',
              },
            ]),
            200,
          );
        }
        if (request.url.path == '/api/shares') {
          return http.Response(
            jsonEncode([
              {
                'id': 'sent-1',
                'path': 'report.pdf',
                'permission': 'read',
                'recipient': 'bob',
                'is_link': false,
                'expires_at': '2026-12-01T10:00:00Z',
              },
            ]),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final api = Api(session, client: client);
      final received = await api.shared();
      final sent = await api.shares();

      expect(received.single['owner'], 'alice');
      expect(received.single['permission'], 'write');
      expect(sent.single['recipient'], 'bob');
      expect(sent.single['expires_at'], '2026-12-01T10:00:00Z');
    });

    test('leaves only the selected shared entry through authenticated DELETE',
        () async {
      final session = await loadSession();
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response('', 204);
      });

      final api = Api(session, client: client);
      const shareId = '11111111-1111-1111-1111-111111111111';
      await api.leaveShare(shareId);

      expect(captured.method, 'DELETE');
      expect(captured.url.path, '/api/shared');
      expect(captured.url.queryParameters['id'], shareId);
      expect(captured.headers['Authorization'], 'Bearer secret-token');
    });
  });

  group('Logout / session clearing', () {
    setUp(() async {
      setUpStorage();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('server_url', 'https://server.com');
      await prefs.setString('display_name', 'Alice');
      await prefs.setString('username', 'alice');
      await prefs.setString('role', 'admin');
      FlutterSecureStorage.setMockInitialValues(
          <String, String>{'token': 'secret-token'});
    });

    test('calls the logout endpoint then clears the persisted session',
        () async {
      final session = await loadSession();
      expect(session.token, isNotNull);
      expect(session.serverUrl, isNotNull);

      var logoutCalled = false;
      final client = MockClient((request) async {
        if (request.url.path == '/api/auth/logout') {
          logoutCalled = true;
          return http.Response('', 204);
        }
        return http.Response('', 404);
      });

      final api = Api(session, client: client);
      await api.logout();

      expect(logoutCalled, isTrue);
      expect(session.token, isNull);
      expect(session.serverUrl, isNull);
      expect(session.username, isNull);
      expect(session.displayName, isNull);
      expect(session.role, isNull);

      // Reloading from storage must not restore the cleared session.
      final reloaded = Session();
      await reloaded.load();
      expect(reloaded.token, isNull);
      expect(reloaded.serverUrl, isNull);
    });
  });

  group('API error handling', () {
    setUp(() async {
      setUpStorage();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('server_url', 'https://server.com');
    });

    test('requests detailed statistics from the dedicated insights endpoint',
        () async {
      final session = await loadSession();
      Uri? requestedUri;
      final client = MockClient((request) async {
        requestedUri = request.url;
        return http.Response(
          jsonEncode({
            'used_bytes': 4096,
            'file_count': 2,
            'quota_bytes': null,
            'type_breakdown': [
              {
                'key': 'images',
                'label': 'Images',
                'bytes': 4096,
                'count': 2,
              },
            ],
            'activity_last_7_days': [],
            'size_distribution': [],
            'largest_files': [],
          }),
          200,
        );
      });

      final api = Api(session, client: client);
      final result = await api.storageInsights();

      expect(requestedUri?.path, '/api/storage/insights');
      expect(result['type_breakdown'], isA<List<dynamic>>());
      expect(result['used_bytes'], 4096);
    });

    test('throws ApiException on non-2xx response with server error', () async {
      final session = await loadSession();
      final client = MockClient((request) async =>
          http.Response(jsonEncode({'error': 'Not found'}), 404));

      final api = Api(session, client: client);
      await expectLater(
        api.storage(),
        throwsA(isA<ApiException>()
            .having((e) => e.status, 'status', 404)
            .having((e) => e.message, 'message', 'Not found')),
      );
    });

    test('throws ApiException on server error status', () async {
      final session = await loadSession();
      final client = MockClient((request) async =>
          http.Response(jsonEncode({'error': 'Internal server error'}), 500));

      final api = Api(session, client: client);
      await expectLater(
        api.storage(),
        throwsA(isA<ApiException>()
            .having((e) => e.status, 'status', 500)
            .having((e) => e.message, 'message', 'Internal server error')),
      );
    });

    test('falls back to a generic message when the body is not JSON', () async {
      final session = await loadSession();
      final client = MockClient(
          (request) async => http.Response('<html>oops</html>', 503));

      final api = Api(session, client: client);
      await expectLater(
        api.storage(),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', 'Request failed (503)')),
      );
    });

    test('fires onUnauthorized on a 401 and still throws', () async {
      setUpStorage();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('server_url', 'https://server.com');
      FlutterSecureStorage.setMockInitialValues(
          <String, String>{'token': 'expired-token'});
      final session = await loadSession();

      var unauthorizedFired = false;
      final client = MockClient((request) async =>
          http.Response(jsonEncode({'error': 'Unauthorized'}), 401));

      final api = Api(session, client: client);
      api.onUnauthorized = () async => unauthorizedFired = true;

      await expectLater(
        api.storage(),
        throwsA(isA<ApiException>()
            .having((e) => e.status, 'status', 401)
            .having((e) => e.message, 'message', 'Unauthorized')),
      );
      expect(unauthorizedFired, isTrue,
          reason: 'onUnauthorized should be invoked when a 401 is returned');
    });
  });
  group('Resumable upload completion', () {
    setUp(() async {
      setUpStorage();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('server_url', 'https://server.com');
      FlutterSecureStorage.setMockInitialValues(
        <String, String>{'token': 'secret-token'},
      );
    });

    test('does not infer completion from a final byte offset', () async {
      final session = await loadSession();
      final api = Api(
        session,
        client: _ImmediateResponseClient(
          http.Response(
            jsonEncode({
              'upload_id': 'upload-1',
              'status': 'receiving',
              'offset': 4,
              'total': 4,
            }),
            200,
          ),
        ),
      );

      await expectLater(
        api.uploadChunk(
          uploadId: 'upload-1',
          folder: 'Phone backup',
          name: 'file.bin',
          offset: 0,
          total: 4,
          bytes: Stream<List<int>>.error(StateError('source stream failed')),
          contentLength: 4,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('accepts a stream error only when the server confirms completion',
        () async {
      final session = await loadSession();
      final api = Api(
        session,
        client: _ImmediateResponseClient(
          http.Response(
            jsonEncode({
              'upload_id': 'upload-1',
              'status': 'completed',
              'offset': 4,
              'total': 4,
              'checksum_sha256': 'expected-checksum',
            }),
            200,
          ),
        ),
      );

      final result = await api.uploadChunk(
        uploadId: 'upload-1',
        folder: 'Phone backup',
        name: 'file.bin',
        offset: 0,
        total: 4,
        bytes: Stream<List<int>>.error(StateError('late local stream error')),
        contentLength: 4,
      );

      expect(result['status'], 'completed');
      expect(result['offset'], 4);
      expect(result['checksum_sha256'], 'expected-checksum');
    });
  });
}
