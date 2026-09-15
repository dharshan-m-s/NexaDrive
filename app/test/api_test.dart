import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexadrive/services/api.dart';
import 'package:nexadrive/services/session.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      expect(Session.normalizeServerUrl('nas.lan:8080'),
          'https://nas.lan:8080');
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

      expect(capturedUri.toString(),
          'https://server.example.com/api/auth/login');
      expect(capturedHeaders['Content-Type'], 'application/json');
      expect(jsonDecode(capturedBody),
          {'username': 'alice', 'password': 'test-pass-123'});
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

    test('does not produce a double slash in the authenticated URL',
        () async {
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

    test('throws ApiException on non-2xx response with server error',
        () async {
      final session = await loadSession();
      final client = MockClient(
          (request) async => http.Response(jsonEncode({'error': 'Not found'}),
              404));

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
      final client = MockClient((request) async => http.Response(
          jsonEncode({'error': 'Internal server error'}), 500));

      final api = Api(session, client: client);
      await expectLater(
        api.storage(),
        throwsA(isA<ApiException>()
            .having((e) => e.status, 'status', 500)
            .having((e) => e.message, 'message', 'Internal server error')),
      );
    });

    test('falls back to a generic message when the body is not JSON',
        () async {
      final session = await loadSession();
      final client =
          MockClient((request) async => http.Response('<html>oops</html>', 503));

      final api = Api(session, client: client);
      await expectLater(
        api.storage(),
        throwsA(isA<ApiException>().having(
            (e) => e.message, 'message', 'Request failed (503)')),
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
      final client = MockClient(
          (request) async => http.Response(jsonEncode({'error': 'Unauthorized'}), 401));

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
}
