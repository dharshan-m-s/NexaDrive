import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nexadrive/core/design/app_theme.dart';
import 'package:nexadrive/core/models/file_entry.dart';
import 'package:nexadrive/services/api.dart';
import 'package:nexadrive/services/session.dart';
import 'package:nexadrive/ui/screens/files/file_share_sheet.dart';
import 'package:nexadrive/ui/screens/files/files_screen.dart';
import 'package:nexadrive/ui/screens/trash/trash_screen.dart';

/// Layout and state regression tests for the redesigned screens.
///
/// These are the checks a golden image cannot make: that nothing overflows at
/// a given size, that empty states are actionable, and that a failed load is
/// never rendered as "there is nothing here".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Session session() {
    final s = Session();
    s.serverUrl = 'https://example.test';
    s.token = 'token';
    s.username = 'admin';
    s.displayName = 'Administrator';
    return s;
  }

  /// An [Api] whose every call fails, standing in for an unreachable server.
  Api offlineApi() => Api(session(), client: _NeverClient());

  /// An [Api] serving a fixed listing.
  Api listingApi(List<Map<String, dynamic>> files) =>
      Api(session(), client: _JsonClient(files));

  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: screen),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  group('Files screen', () {
    testWidgets('an empty folder offers a real next action', (tester) async {
      await pump(tester, FilesScreen(api: listingApi(const [])));
      expect(find.text('Your cloud is empty'), findsOneWidget);
      expect(find.text('Upload files'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failed listing is an error state, not an empty state',
        (tester) async {
      await pump(tester, FilesScreen(api: offlineApi()));
      expect(find.textContaining('reach NexaDrive'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      // The empty-folder copy must not appear when the load failed.
      expect(find.text('Your cloud is empty'), findsNothing);
      expect(find.text('This folder is empty'), findsNothing);
    });

    testWidgets('the header fits a 320dp phone without overflowing',
        (tester) async {
      await pump(
        tester,
        FilesScreen(
          api: listingApi([
            {
              'name': 'A very long folder name that keeps going and going',
              'path': 'A very long folder name that keeps going and going',
              'kind': 'folder',
              'size': 0,
            },
          ]),
        ),
        size: const Size(320, 640),
      );
      expect(tester.takeException(), isNull);
      // Three compact controls replaced the previous seven-icon row.
      expect(find.byTooltip('Upload files'), findsOneWidget);
      expect(find.byTooltip('Search files'), findsOneWidget);
      expect(find.byTooltip('More actions'), findsOneWidget);
    });

    testWidgets('breadcrumb crumbs meet the 48dp touch-target floor',
        (tester) async {
      await pump(
        tester,
        FilesScreen(api: listingApi(const []), initialPath: 'Photos/2026'),
      );
      final crumb = find.text('Photos');
      expect(crumb, findsOneWidget);
      final size = tester.getSize(
        find.ancestor(of: crumb, matching: find.byType(InkWell)).first,
      );
      expect(size.height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
    });
  });

  group('Trash screen', () {
    testWidgets('a failed load is not rendered as an empty trash',
        (tester) async {
      await pump(tester, TrashScreen(api: offlineApi()));
      expect(find.text('Trash is empty'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Share sheet', () {
    testWidgets('a multi-file selection promises exactly what it creates',
        (tester) async {
      final files = [
        const FileEntry(name: 'a.jpg', path: 'a.jpg', type: 'file'),
        const FileEntry(name: 'b.jpg', path: 'b.jpg', type: 'file'),
        const FileEntry(name: 'c.jpg', path: 'c.jpg', type: 'file'),
      ];
      await pump(
        tester,
        FileShareSheet(api: offlineApi(), files: files),
        size: const Size(390, 900),
      );
      expect(find.text('Share 3 items'), findsOneWidget);
      expect(find.text('Each file gets its own link'), findsOneWidget);
      expect(find.text('Create 3 links'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('folders are offered a person share, never a public link',
        (tester) async {
      await pump(
        tester,
        FileShareSheet(
          api: offlineApi(),
          files: const [
            FileEntry(name: 'Archive', path: 'Archive', type: 'folder'),
          ],
        ),
        size: const Size(390, 900),
      );
      // Link mode is not offered at all for a folder.
      expect(find.text('Anyone with link'), findsNothing);
      expect(find.text('NexaDrive username'), findsOneWidget);
      expect(find.text('Share with person'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('dark mode', () {
    testWidgets('the shell screens render in dark mode without error',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: FilesScreen(api: listingApi(const [])),
          ),
        ),
      );
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(tester.takeException(), isNull);
      expect(find.text('Your cloud is empty'), findsOneWidget);
    });
  });
}

/// Minimal HTTP client that fails every request, so [Api] surfaces a transport
/// error exactly as it would against an unreachable server.
class _NeverClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return Future.error(const _TransportFailure());
  }
}

/// Stands in for a socket failure without needing dart:io platform channels.
class _TransportFailure implements Exception {
  const _TransportFailure();
  @override
  String toString() => 'Connection refused';
}

/// Returns a fixed JSON array for every GET.
class _JsonClient extends http.BaseClient {
  _JsonClient(this.body);
  final List<Map<String, dynamic>> body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}
