import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexadrive/core/design/app_theme.dart';
import 'package:nexadrive/services/api.dart';
import 'package:nexadrive/services/session.dart';
import 'package:nexadrive/ui/screens/search/search_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Session session() {
  final s = Session();
  s.serverUrl = 'https://example.test';
  s.token = 'token';
  return s;
}

/// Calm search slice: recents, compact filters and warm, actionable states.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const recentKey = 'nexadrive.search.recent_queries';

  Future<void> pumpScreen(
    WidgetTester tester,
    _SearchApi api, {
    String initialQuery = '',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SearchScreen(api: api, initialQuery: initialQuery),
      ),
    );
    // Let the post-frame initial query, its debounce and the response settle.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  Future<void> typeQuery(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  Future<void> clearQuery(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
  }

  testWidgets('before typing it is quiet and does not search', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = _SearchApi();
    await pumpScreen(tester, api);

    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(find.text('Recent searches'), findsNothing);
    expect(find.text('Clear recent'), findsNothing);
    expect(api.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stored recents appear with a clear action', (tester) async {
    SharedPreferences.setMockInitialValues({
      recentKey: ['invoice', 'Photos'],
    });
    final api = _SearchApi();
    await pumpScreen(tester, api);

    expect(find.text('Recent searches'), findsOneWidget);
    expect(find.text('invoice'), findsOneWidget);
    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Clear recent'), findsOneWidget);

    await tester.tap(find.text('Clear recent'));
    await tester.pumpAndSettle();
    expect(find.text('invoice'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(recentKey), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recents de-duplicate case-insensitively and cap at six',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = _SearchApi()
      ..respond = (_) async => [
            {'name': 'result.txt', 'path': 'result.txt', 'type': 'file'},
          ];
    await pumpScreen(tester, api);

    for (final query in [
      'one',
      'two',
      'three',
      'four',
      'five',
      'six',
      'ONE',
      'seven',
    ]) {
      await clearQuery(tester);
      await typeQuery(tester, query);
    }
    await clearQuery(tester);

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(recentKey)!;
    expect(saved, hasLength(6));
    expect(saved.first, 'seven');
    expect(saved.where((q) => q.toLowerCase() == 'one'), hasLength(1));
    expect(find.text('seven'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an error explains what failed and retry re-runs the query',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = _SearchApi();
    var attempts = 0;
    api.respond = (query) async {
      attempts++;
      if (attempts == 1) throw Exception('offline');
      return [
        {'name': 'Docs', 'path': 'Docs', 'type': 'folder'},
        {'name': 'report.txt', 'path': 'report.txt', 'type': 'file'},
      ];
    };
    await pumpScreen(tester, api, initialQuery: 'report');

    expect(find.text("Search didn't finish — try again"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('2 matching items'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(api.calls, ['report', 'report']);
    expect(find.text('2 matching items'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filters live in the header and narrow results in place',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = _SearchApi()
      ..respond = (_) async => [
            {'name': 'Docs', 'path': 'Docs', 'type': 'folder'},
            {'name': 'notes.txt', 'path': 'notes.txt', 'type': 'file'},
          ];
    await pumpScreen(tester, api, initialQuery: 'do');

    expect(find.text('2 matching items'), findsOneWidget);
    await tester.tap(find.text('Folders 1'));
    await tester.pumpAndSettle();
    expect(find.text('1 matching item'), findsOneWidget);
    expect(find.text('Docs'), findsOneWidget);
    expect(find.text('notes.txt'), findsNothing);

    await tester.tap(find.text('All 2'));
    await tester.pumpAndSettle();
    expect(find.text('notes.txt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty filter offers a way back to all results',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = _SearchApi()
      ..respond = (_) async => [
            {'name': 'notes.txt', 'path': 'notes.txt', 'type': 'file'},
          ];
    await pumpScreen(tester, api, initialQuery: 'notes');

    await tester.tap(find.text('Folders 0'));
    await tester.pumpAndSettle();
    expect(find.text('No folders found'), findsOneWidget);
    await tester.tap(find.text('Show all results'));
    await tester.pumpAndSettle();
    expect(find.text('1 matching item'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a completed search with no hits gets warm no-match copy',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = _SearchApi()..respond = (_) async => [];
    await pumpScreen(tester, api, initialQuery: 'zzz');

    expect(find.textContaining('No matches for'), findsOneWidget);
    expect(find.byTooltip('Clear search'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _SearchApi extends Api {
  _SearchApi() : super(session());

  final List<String> calls = <String>[];
  Future<List<Map<String, dynamic>>> Function(String query)? respond;

  @override
  Future<List<Map<String, dynamic>>> searchFiles(String query) async {
    calls.add(query);
    final handler = respond;
    if (handler == null) return const <Map<String, dynamic>>[];
    return handler(query);
  }
}
