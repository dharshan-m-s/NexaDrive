import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexadrive/core/design/app_theme.dart';
import 'package:nexadrive/services/api.dart';
import 'package:nexadrive/services/session.dart';
import 'package:nexadrive/services/sync_service.dart';
import 'package:nexadrive/ui/screens/sync/sync_center_screen.dart';
import 'package:nexadrive/ui/widgets/nexa_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Focused guards for Sync Center's state copy, conflict ordering and retry
/// paths. The sync engine itself has its own end-to-end tests; these only pin
/// the readable state the screen presents.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late Api api;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SyncManager.resetDeviceIdCache();
    prefs = await SharedPreferences.getInstance();
    api = _buildApi();
  });

  group('conflict ordering', () {
    test('newest conflicts come first when timestamps are available', () async {
      await prefs.setString(
        'sync_state_v1',
        jsonEncode({
          'old.txt': {
            'conflict': true,
            'conflictPath': '/tmp/old.txt.conflict-1000',
          },
          'new.txt': {
            'conflict': true,
            'conflictPath': '/tmp/new.txt.conflict-3000',
          },
          'middle.txt': {
            'conflict': true,
            'conflictPath': '/tmp/middle.txt.conflict-2000',
          },
        }),
      );

      final conflicts = await SyncManager(api).conflicts();

      expect(
        conflicts.map((item) => item['path']).toList(),
        ['new.txt', 'middle.txt', 'old.txt'],
      );
    });

    test('conflicts without timestamps fall back to path order', () async {
      await prefs.setString(
        'sync_state_v1',
        jsonEncode({
          'zeta.txt': {'conflict': true},
          'alpha.txt': {'conflict': true},
        }),
      );

      final conflicts = await SyncManager(api).conflicts();

      expect(
        conflicts.map((item) => item['path']).toList(),
        ['alpha.txt', 'zeta.txt'],
      );
    });
  });

  testWidgets('state copy is shared by the header and the status card',
      (tester) async {
    await prefs.setString('sync_folder_v1', '/tmp/nexadrive-sync');
    await prefs.setString(
      'sync_state_v1',
      jsonEncode({
        '__meta__': {
          'lastSyncAt': DateTime.now()
              .subtract(const Duration(minutes: 4, seconds: 5))
              .toUtc()
              .toIso8601String(),
        },
      }),
    );

    await _pump(tester, api);

    expect(find.text('Last synced 4 minutes ago'), findsOneWidget);
    expect(find.text('Everything is synced'), findsOneWidget);
    expect(
      find.text('This device is up to date. Last synced 4 minutes ago.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('conflicts are the first content section with plain consequences',
      (tester) async {
    await prefs.setString('sync_folder_v1', '/tmp/nexadrive-sync');
    await prefs.setString(
      'sync_state_v1',
      jsonEncode({
        'docs/quarterly report.txt': {
          'conflict': true,
          'conflictPath': '/tmp/quarterly report.txt.conflict-3000',
        },
        'photos/holiday.txt': {
          'conflict': true,
          'conflictPath': '/tmp/holiday.txt.conflict-2000',
        },
      }),
    );

    await _pump(tester, api);

    expect(find.text('2 folders need attention'), findsNWidgets(2));
    expect(
      find.text('Both versions changed. Keep the one you want.'),
      findsOneWidget,
    );
    expect(find.text('quarterly report.txt'), findsOneWidget);
    expect(find.text('docs/quarterly report.txt'), findsOneWidget);
    expect(
      find.textContaining('Keep mine uploads your copy; keep cloud replaces'),
      findsNWidgets(2),
    );

    final decision = tester.getRect(find.text('Needs your decision'));
    final folders = tester.getRect(find.text('Synced folder'));
    expect(decision.top, lessThan(folders.top),
        reason: 'the files waiting on a decision must be above folder setup');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a device-list retry keeps local settings on screen',
      (tester) async {
    await prefs.setString('sync_folder_v1', '/tmp/keep-visible');
    var attempts = 0;
    final failingThenWorking = _buildApi(onRequest: (request) async {
      if (request.url.path != '/api/sync/devices') {
        return _json({'error': 'unexpected request'}, 500);
      }
      attempts++;
      if (attempts == 1) {
        return http.Response('boom', 500);
      }
      return _json([
        {
          'id': 'desk-1',
          'name': 'Desk',
          'platform': 'linux',
          'last_seen_at': DateTime.now().toUtc().toIso8601String(),
        },
      ]);
    });

    await _pump(tester, failingThenWorking);

    expect(find.text('Linked devices are unavailable'), findsOneWidget);
    expect(
        find.textContaining('folder settings are still here'), findsOneWidget);
    expect(find.text('/tmp/keep-visible'), findsOneWidget);

    final retry = find.widgetWithText(NexaTextButton, 'Retry');
    expect(retry, findsOneWidget);
    await tester.tap(retry);
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('Linked devices are unavailable'), findsNothing);
    expect(find.text('Desk'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offline device list is calm, obvious and retryable',
      (tester) async {
    await prefs.setString('sync_folder_v1', '/tmp/keep-visible');
    final offline = _buildApi(onRequest: (request) async {
      throw SocketException('Network is unreachable');
    });

    await _pump(tester, offline);

    expect(find.text('Linked devices are unavailable'), findsOneWidget);
    expect(find.textContaining('You appear to be offline'), findsOneWidget);
    expect(
      find.widgetWithText(NexaTextButton, 'Retry'),
      findsOneWidget,
      reason: 'even a calm offline notice needs one clear way forward',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a local settings failure offers a full-page retry',
      (tester) async {
    await prefs.setString('sync_folder_v1', '/tmp/nexadrive-sync');
    await prefs.setString('sync_state_v1', '{not-json');

    await _pump(tester, api);

    expect(find.text('We couldn’t load your sync settings'), findsOneWidget);
    final retry = find.widgetWithText(NexaFilledButton, 'Retry');
    expect(retry, findsOneWidget);

    await prefs.setString(
      'sync_state_v1',
      jsonEncode({
        '__meta__': {
          'lastSyncAt': DateTime.now().toUtc().toIso8601String(),
        },
      }),
    );
    await tester.tap(retry);
    await tester.pumpAndSettle();

    expect(find.text('Everything is synced'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Api _buildApi({
  Future<http.Response> Function(http.Request request)? onRequest,
}) {
  final session = Session()
    ..serverUrl = 'https://example.test'
    ..token = 'test-token';
  return Api(
    session,
    client: MockClient((request) async {
      if (onRequest != null) return onRequest(request);
      if (request.url.path == '/api/sync/devices') return _json([]);
      return _json({'error': 'unexpected request'}, 500);
    }),
  );
}

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

Future<void> _pump(WidgetTester tester, Api api) async {
  await tester.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Scaffold(body: SyncCenterScreen(api: api)),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}
