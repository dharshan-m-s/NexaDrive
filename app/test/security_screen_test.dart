import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexadrive/core/design/app_theme.dart';
import 'package:nexadrive/services/api.dart';
import 'package:nexadrive/services/session.dart';
import 'package:nexadrive/ui/screens/login/login_screen.dart';
import 'package:nexadrive/ui/screens/settings/security_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A scripted [Api] that serves a fixed session list and records every
/// sign-out call, without touching a server.
class _ScriptedApi extends Api {
  _ScriptedApi({
    List<Map<String, dynamic>>? sessionsResult,
    this.sessionsError,
    this.revokeError,
  })  : _sessions = sessionsResult ?? _defaultSessions(),
        super(_session());

  List<Map<String, dynamic>> _sessions;
  final Object? sessionsError;
  final Object? revokeError;

  final List<String> calls = [];

  static Session _session() {
    final s = Session()
      ..serverUrl = 'https://example.com'
      ..token = 'tok'
      ..username = 'alice';
    s.userId = 'self';
    return s;
  }

  static List<Map<String, dynamic>> _defaultSessions() => [
        {
          'session_id': 'other-1',
          'created_at': '2026-10-01T10:00:00Z',
          'last_activity_at': '2026-10-11T08:00:00Z',
          'expires_at': '2026-11-01T10:00:00Z',
          'is_current': false,
          'device_name': 'Living room PC',
          'platform': 'windows',
        },
        {
          'session_id': 'current-1',
          'created_at': '2026-10-02T10:00:00Z',
          'last_activity_at': '2026-10-12T09:00:00Z',
          'expires_at': '2026-11-02T10:00:00Z',
          'is_current': true,
          'device_name': 'Pixel 8',
          'platform': 'android',
        },
        {
          'session_id': 'other-2',
          'created_at': '2026-10-03T10:00:00Z',
          'last_activity_at': '2026-10-10T08:00:00Z',
          'expires_at': '2026-11-03T10:00:00Z',
          'is_current': false,
          'device_name': 'Work laptop',
          'platform': 'linux',
        },
      ];

  @override
  Future<List<Map<String, dynamic>>> sessions() async {
    calls.add('sessions');
    if (sessionsError != null) throw sessionsError!;
    return _sessions;
  }

  @override
  Future<void> revokeSession(String sessionId) async {
    calls.add('revokeSession:$sessionId');
    if (revokeError != null) throw revokeError!;
    _sessions = _sessions.where((s) => s['session_id'] != sessionId).toList();
  }

  @override
  Future<void> revokeOtherSessions() async {
    calls.add('revokeOtherSessions');
    if (revokeError != null) throw revokeError!;
    _sessions = _sessions.where((s) => s['is_current'] == true).toList();
  }

  @override
  Future<void> signOutEverywhere() async {
    calls.add('signOutEverywhere');
    if (revokeError != null) throw revokeError!;
    _sessions = [];
  }
}

Future<void> _pump(
    WidgetTester tester, _ScriptedApi api, Session session) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    home: Scaffold(body: SecurityScreen(session: session, api: api)),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('viewing sessions', () {
    testWidgets('lists every session, current one labelled This device',
        (tester) async {
      final api = _ScriptedApi();
      await _pump(tester, api, api.session);
      await tester.pumpAndSettle();

      // The current session is present and marked.
      expect(find.text('This device'), findsOneWidget);
      expect(find.text('Pixel 8'), findsOneWidget);
      // Every other session is listed by its device name.
      expect(find.text('Living room PC'), findsOneWidget);
      expect(find.text('Work laptop'), findsOneWidget);
      // Sections explain the structure (section headers render uppercased).
      expect(find.text('OTHER SESSIONS'), findsOneWidget);
      expect(find.text('SIGN OUT'), findsOneWidget);
      expect(find.text('Sign out'), findsWidgets);
    });

    testWidgets('the current session leads the list', (tester) async {
      final api = _ScriptedApi();
      await _pump(tester, api, api.session);
      await tester.pumpAndSettle();

      final current = tester.getTopLeft(find.text('This device'));
      final other = tester.getTopLeft(find.text('Living room PC'));
      expect(current.dy, lessThan(other.dy));
    });

    testWidgets('a load failure explains itself and can retry', (tester) async {
      final api = _ScriptedApi(sessionsError: ApiException(500, 'boom'));
      await _pump(tester, api, api.session);
      await tester.pumpAndSettle();

      expect(find.text('Can\u2019t load sessions'), findsOneWidget);
      expect(find.text('boom'), findsOneWidget);

      // Retry once the server recovers.
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(api.calls.where((c) => c == 'sessions'), hasLength(2));
    });
  });

  group('revoking unwanted sessions', () {
    testWidgets('revoking another session asks, calls, and refreshes',
        (tester) async {
      final api = _ScriptedApi();
      await _pump(tester, api, api.session);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Sign out').first);
      await tester.pumpAndSettle();

      // Destructive action is confirmed first, naming the device.
      expect(find.textContaining('Living room PC'), findsWidgets);
      expect(find.text('Sign out'), findsWidgets);
      await tester.tap(find.text('Sign out').last);
      await tester.pumpAndSettle();

      expect(api.calls, contains('revokeSession:other-1'));
      // The list refreshes without the revoked session.
      expect(find.text('Living room PC'), findsNothing);
      expect(find.text('Work laptop'), findsOneWidget);
      expect(find.text('Pixel 8'), findsOneWidget);
      expect(find.text('Signed out Living room PC'), findsOneWidget);
    });

    testWidgets('cancelling the confirmation revokes nothing', (tester) async {
      final api = _ScriptedApi();
      await _pump(tester, api, api.session);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Sign out').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(api.calls.where((c) => c.startsWith('revokeSession')), isEmpty);
      expect(find.text('Living room PC'), findsOneWidget);
    });

    testWidgets('a failed revoke surfaces an error, not a cleared list',
        (tester) async {
      final api = _ScriptedApi(revokeError: ApiException(409, 'Busy'));
      await _pump(tester, api, api.session);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Sign out').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out').last);
      await tester.pumpAndSettle();

      expect(find.text('Busy'), findsOneWidget);
      // The list still shows every session: nothing silently vanished.
      expect(find.text('Living room PC'), findsOneWidget);
      expect(find.text('Work laptop'), findsOneWidget);
    });

    testWidgets('sign out of other sessions keeps this device signed in',
        (tester) async {
      final api = _ScriptedApi();
      await _pump(tester, api, api.session);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign out of other sessions'));
      await tester.pumpAndSettle();
      expect(find.text('Sign out of other sessions'), findsWidgets);
      // Confirm in the dialog (the second occurrence of the label).
      await tester.tap(find.text('Sign out of other sessions').last);
      await tester.pumpAndSettle();

      expect(api.calls, contains('revokeOtherSessions'));
      expect(find.text('Living room PC'), findsNothing);
      expect(find.text('Work laptop'), findsNothing);
      // This device survives.
      expect(find.text('This device'), findsOneWidget);
      expect(find.text('Other sessions signed out'), findsOneWidget);
    });
  });

  group('ending this device', () {
    testWidgets('revoking the current session clears it and returns to sign-in',
        (tester) async {
      final api = _ScriptedApi();
      await _pump(tester, api, api.session);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Sign out of this device'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out').last);
      await tester.pumpAndSettle();

      expect(api.calls, contains('revokeSession:current-1'));
      expect(api.session.token, isNull);
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('sign out everywhere clears the local session too',
        (tester) async {
      final api = _ScriptedApi();
      await _pump(tester, api, api.session);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign out everywhere'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out everywhere').last);
      await tester.pumpAndSettle();

      expect(api.calls, contains('signOutEverywhere'));
      expect(api.session.token, isNull);
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });
}
