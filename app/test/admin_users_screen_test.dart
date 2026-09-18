import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexadrive/core/design/app_theme.dart';
import 'package:nexadrive/services/api.dart';
import 'package:nexadrive/services/session.dart';
import 'package:nexadrive/ui/screens/admin/admin_users_screen.dart';

/// A scripted [Api] so the screen can be driven through every state without a
/// server. Only the account methods are overridden.
class _ScriptedApi extends Api {
  _ScriptedApi({
    this.usersResult,
    this.usersError,
    this.neverCompletes = false,
    String? selfId,
    String? selfUsername,
  }) : super(_session(selfId, selfUsername));

  final List<Map<String, dynamic>>? usersResult;
  final Object? usersError;
  final bool neverCompletes;

  final List<String> calls = [];

  static Session _session(String? id, String? username) {
    final s = Session()
      ..serverUrl = 'https://example.com'
      ..token = 'tok'
      ..username = username ?? 'root';
    s.userId = id ?? 'self';
    return s;
  }

  @override
  Future<List<Map<String, dynamic>>> users() async {
    calls.add('users');
    if (neverCompletes) return Completer<List<Map<String, dynamic>>>().future;
    if (usersError != null) throw usersError!;
    return usersResult ?? const [];
  }

  @override
  Future<void> updateUser(
    String id, {
    String? displayName,
    String? role,
    bool? disabled,
    int? quotaBytes,
    bool clearQuota = false,
    String? password,
  }) async {
    calls.add('updateUser:$id:disabled=$disabled:clearQuota=$clearQuota');
  }

  @override
  Future<void> deleteUser(String id) async => calls.add('deleteUser:$id');

  @override
  Future<void> revokeUserSessions(String id) async =>
      calls.add('revokeUserSessions:$id');
}

Map<String, dynamic> _user({
  required String id,
  required String username,
  String? displayName,
  String role = 'user',
  bool disabled = false,
  int? quotaBytes,
}) =>
    {
      'id': id,
      'username': username,
      'display_name': displayName ?? username,
      'role': role,
      'disabled': disabled,
      'quota_bytes': quotaBytes,
    };

const _gib = 1024 * 1024 * 1024;

Future<void> _pump(WidgetTester tester, _ScriptedApi api) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    home: Scaffold(body: AdminUsersScreen(api: api)),
  ));
}

/// The failure the screen must never present as "0 accounts".
void _expectNoZeroCount() {
  expect(find.textContaining('0 account'), findsNothing,
      reason: 'a failed or in-flight load must never render a zero count');
}

void main() {
  group('the page always states what it is for', () {
    testWidgets('header shows its purpose', (tester) async {
      await _pump(tester, _ScriptedApi(usersResult: const []));
      await tester.pumpAndSettle();
      expect(find.text('Users'), findsOneWidget);
      expect(find.text('Manage accounts and access'), findsOneWidget);
    });
  });

  group('in-flight load', () {
    testWidgets('shows progress, never a zero count', (tester) async {
      await _pump(tester, _ScriptedApi(neverCompletes: true));
      await tester.pump();
      expect(find.text('Loading accounts…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      _expectNoZeroCount();
    });
  });

  group('failures are distinct from emptiness', () {
    testWidgets('403 explains that administrator access is required',
        (tester) async {
      await _pump(
        tester,
        _ScriptedApi(usersError: ApiException(403, 'Forbidden')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Administrator access required'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      _expectNoZeroCount();
    });

    testWidgets('401 explains the session expired', (tester) async {
      await _pump(
        tester,
        _ScriptedApi(usersError: ApiException(401, 'Unauthorized')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your session expired'), findsOneWidget);
      _expectNoZeroCount();
    });

    testWidgets('5xx is reported as a server problem, not the user\'s',
        (tester) async {
      await _pump(
        tester,
        _ScriptedApi(usersError: ApiException(500, 'Internal error')),
      );
      await tester.pumpAndSettle();
      expect(find.text('The server couldn\u2019t load accounts'), findsOneWidget);
      expect(find.textContaining('Internal error'), findsOneWidget);
      _expectNoZeroCount();
    });

    testWidgets('a transport failure says the server is unreachable',
        (tester) async {
      await _pump(
        tester,
        _ScriptedApi(usersError: Exception('SocketException: failed')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Can\u2019t reach the server'), findsOneWidget);
      _expectNoZeroCount();
    });

    testWidgets('retry re-requests and recovers', (tester) async {
      final api = _ScriptedApi(usersError: ApiException(500, 'boom'));
      await _pump(tester, api);
      await tester.pumpAndSettle();
      expect(api.calls.where((c) => c == 'users'), hasLength(1));

      // Retry — the scripted api keeps failing, so it must stay in the failed
      // state rather than flip to an empty list.
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(api.calls.where((c) => c == 'users'), hasLength(2));
      expect(find.text('The server couldn\u2019t load accounts'), findsOneWidget);
      _expectNoZeroCount();
    });
  });

  group('genuinely empty instance', () {
    testWidgets('offers a first-account action instead of a void',
        (tester) async {
      await _pump(tester, _ScriptedApi(usersResult: const []));
      await tester.pumpAndSettle();
      expect(find.text('No accounts yet'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Add user'), findsOneWidget);
      // Grouped-list headers are rendered as uppercase micro-labels.
      expect(find.text('ROLES'), findsOneWidget);
      expect(find.text('ACCOUNTS'), findsOneWidget);
    });

    testWidgets('is anchored under the header, not centred in the viewport',
        (tester) async {
      await _pump(tester, _ScriptedApi(usersResult: const []));
      await tester.pumpAndSettle();
      final header = tester.getBottomLeft(find.text('Manage accounts and access'));
      final empty = tester.getTopLeft(find.text('No accounts yet'));
      // The empty-state panel starts within a header-height of the page title
      // rather than being pushed to the middle of an 844px screen.
      expect(empty.dy - header.dy, lessThan(96));
    });
  });

  group('populated instance', () {
    _ScriptedApi scripted() => _ScriptedApi(
          usersResult: [
            _user(
              id: 'self',
              username: 'root',
              displayName: 'Administrator',
              role: 'admin',
              quotaBytes: 25 * _gib,
            ),
            _user(
              id: '2',
              username: 'grace',
              displayName: 'Grace Hopper',
            ),
            _user(id: '3', username: 'alex', displayName: 'Alex', disabled: true),
          ],
        );

    testWidgets('summarises counts by kind', (tester) async {
      await _pump(tester, scripted());
      await tester.pumpAndSettle();
      expect(find.textContaining('3 accounts'), findsOneWidget);
      expect(find.textContaining('1 administrator'), findsOneWidget);
      expect(find.textContaining('1 blocked'), findsOneWidget);
    });

    testWidgets('shows identity, role and storage per row', (tester) async {
      await _pump(tester, scripted());
      await tester.pumpAndSettle();
      expect(find.text('Grace Hopper'), findsOneWidget);
      expect(find.textContaining('@grace'), findsOneWidget);
      expect(find.textContaining('Unlimited storage'), findsWidgets);
      expect(find.textContaining('25 GB'), findsOneWidget);
      expect(find.text('Admin'), findsOneWidget);
      expect(find.text('Blocked'), findsOneWidget);
    });

    testWidgets('marks the signed-in account', (tester) async {
      await _pump(tester, scripted());
      await tester.pumpAndSettle();
      expect(find.text('You'), findsOneWidget);
    });

    testWidgets('a blocked account keeps a full action menu', (tester) async {
      // Regression: blocked rows used to lose every action, making a blocked
      // account impossible to unblock, edit or delete from the app.
      await _pump(tester, scripted());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Account actions').at(2));
      await tester.pumpAndSettle();
      expect(find.text('Unblock account'), findsOneWidget);
      expect(find.text('Edit account'), findsOneWidget);
      expect(find.text('Delete account'), findsOneWidget);
    });

    testWidgets('search narrows the list and can be cleared', (tester) async {
      await _pump(tester, scripted());
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(SearchBar), 'grace');
      await tester.pumpAndSettle();
      expect(find.text('Grace Hopper'), findsOneWidget);
      expect(find.text('Alex'), findsNothing);

      await tester.enterText(find.byType(SearchBar), 'nobody');
      await tester.pumpAndSettle();
      expect(find.textContaining('No accounts match'), findsOneWidget);
    });
  });

  group('administrator protection is enforced in the UI', () {
    testWidgets('deleting your own account is explained, not attempted',
        (tester) async {
      final api = _ScriptedApi(
        usersResult: [
          _user(id: 'self', username: 'root', role: 'admin'),
          _user(id: '2', username: 'ops', role: 'admin'),
        ],
      );
      await _pump(tester, api);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Account actions').at(0));
      await tester.pumpAndSettle();
      // The reason is stated in the menu before anything is tapped.
      expect(find.textContaining('signed in'), findsWidgets);

      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      expect(find.text('This account is protected'), findsOneWidget);
      expect(api.calls.where((c) => c.startsWith('deleteUser')), isEmpty);
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
    });

    testWidgets('the last administrator cannot be deleted', (tester) async {
      final api = _ScriptedApi(
        usersResult: [
          _user(id: '2', username: 'ops'), // signed in as a non-admin
          _user(id: 'root', username: 'root', role: 'admin'),
        ],
        selfId: '2',
        selfUsername: 'ops',
      );
      await _pump(tester, api);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Account actions').at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      expect(find.textContaining('only administrator'), findsWidgets);
      expect(api.calls.where((c) => c.startsWith('deleteUser')), isEmpty);
    });

    testWidgets('an ordinary account can be deleted after confirmation',
        (tester) async {
      final api = _ScriptedApi(
        usersResult: [
          _user(id: 'self', username: 'root', role: 'admin'),
          _user(id: '2', username: 'grace', displayName: 'Grace Hopper'),
        ],
      );
      await _pump(tester, api);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Account actions').at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();

      // Deletion is never one tap: the confirmation names the account and the
      // consequence.
      expect(find.text('Delete Grace Hopper?'), findsOneWidget);
      expect(find.textContaining('cannot be undone'), findsOneWidget);
      await tester.tap(find.text('Delete account').last);
      await tester.pumpAndSettle();
      expect(api.calls, contains('deleteUser:2'));
    });
  });

  group('account editing', () {
    testWidgets('opens with existing values loaded', (tester) async {
      await _pump(
        tester,
        _ScriptedApi(
          usersResult: [
            _user(id: 'self', username: 'root', role: 'admin'),
            _user(
              id: '2',
              username: 'grace',
              displayName: 'Grace Hopper',
              quotaBytes: 10 * _gib,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Grace Hopper'));
      await tester.pumpAndSettle();

      expect(find.text('Edit account'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Grace Hopper'), findsOneWidget);
      expect(find.widgetWithText(TextField, '10'), findsOneWidget);
      // The username is immutable, so it is shown rather than edited.
      expect(find.text('grace'), findsOneWidget);
      expect(find.text('Save changes'), findsOneWidget);
    });

    testWidgets('validation happens before any request', (tester) async {
      final api = _ScriptedApi(
        usersResult: [
          _user(id: 'self', username: 'root', role: 'admin'),
          _user(id: '2', username: 'grace', displayName: 'Grace Hopper'),
        ],
      );
      await _pump(tester, api);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Grace Hopper'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'Grace Hopper'), '');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a display name'), findsOneWidget);
      expect(api.calls.where((c) => c.startsWith('updateUser')), isEmpty);
    });

    testWidgets('clearing the quota asks the server to make it unlimited',
        (tester) async {
      final api = _ScriptedApi(
        usersResult: [
          _user(id: 'self', username: 'root', role: 'admin'),
          _user(
            id: '2',
            username: 'grace',
            displayName: 'Grace Hopper',
            quotaBytes: 10 * _gib,
          ),
        ],
      );
      await _pump(tester, api);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Grace Hopper'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, '10'), '');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      // Regression: the client previously could not clear a quota at all —
      // an empty field sent no quota field, which the server reads as
      // "leave unchanged".
      expect(api.calls, contains('updateUser:2:disabled=false:clearQuota=true'));
    });
  });
}
