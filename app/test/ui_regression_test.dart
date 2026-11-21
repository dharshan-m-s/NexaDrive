import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexadrive/core/design/app_colors.dart';
import 'package:nexadrive/core/design/app_theme.dart';
import 'package:nexadrive/core/models/file_entry.dart';
import 'package:nexadrive/main.dart';
import 'package:nexadrive/services/api.dart';
import 'package:nexadrive/services/session.dart';
import 'package:nexadrive/services/upload_item.dart';
import 'package:nexadrive/services/upload_manager.dart';
import 'package:nexadrive/services/upload_store.dart';
import 'package:nexadrive/ui/screens/files/file_share_sheet.dart';
import 'package:nexadrive/ui/screens/home/home_screen.dart';
import 'package:nexadrive/ui/screens/files/files_screen.dart';
import 'package:nexadrive/ui/screens/trash/trash_screen.dart';
import 'package:nexadrive/ui/shell/app_shell.dart';
import 'package:nexadrive/ui/widgets/active_transfer_strip.dart';
import 'package:nexadrive/ui/widgets/nexa_pill_notice.dart';
import 'package:nexadrive/ui/widgets/upload_progress_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// The More overlay's scrim is the only 32%-alpha ColoredBox in the shell.
  Finder moreScrim() => find.byWidgetPredicate(
        (widget) =>
            widget is ColoredBox &&
            (widget.color.a * 255).round().clamp(0, 255) == 82,
      );

  group('Home screen', () {
    testWidgets('quick actions do not inherit pill clearance as trailing space',
        (tester) async {
      tester.view.physicalSize = const Size(720, 1560);
      tester.view.devicePixelRatio = 1.75;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final files = <Map<String, dynamic>>[
        for (var i = 0; i < 3; i++)
          {
            'name': 'file$i.jpg',
            'path': 'file$i.jpg',
            'type': 'file',
            'size': 1000,
            'modified_at': '2026-11-21T10:0$i:00Z',
          },
      ];
      final api = Api(
        session(),
        client: MockClient((request) async {
          final path = request.url.path;
          Object body;
          if (path.endsWith('/api/storage')) {
            body = {
              'used_bytes': 1000,
              'file_count': 24,
              'quota_bytes': null,
            };
          } else if (path.endsWith('/api/files')) {
            body = files;
          } else {
            body = <Object>[];
          }
          return http.Response.bytes(
            utf8.encode(jsonEncode(body)),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      // The shell exposes floating-pill clearance through MediaQuery padding.
      // A scrollable grid must not consume it as trailing sliver padding.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: MediaQueryData(
              padding: const EdgeInsets.only(bottom: 130),
            ),
            child: Scaffold(
              body: HomeScreen(
                session: session(),
                api: api,
                onNavigate: (_) {},
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();

      final grid = tester.renderObject<RenderBox>(find.byType(GridView));
      final gridBottom = grid.localToGlobal(Offset.zero).dy + grid.size.height;
      final recentTop = tester.getTopLeft(find.text('RECENT')).dy;
      expect(recentTop - gridBottom, greaterThanOrEqualTo(24));
      expect(recentTop - gridBottom, lessThan(60));
      expect(tester.takeException(), isNull);
    });
  });

  group('Files screen', () {
    testWidgets('an empty folder offers a real next action', (tester) async {
      await pump(tester, FilesScreen(api: listingApi(const [])));
      expect(find.text('Your cloud is empty'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Your cloud is empty')).dy,
        lessThan(280),
      );
      expect(find.text('Upload files'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failed listing is an error state, not an empty state',
        (tester) async {
      await pump(tester, FilesScreen(api: offlineApi()));
      expect(find.textContaining('reach NexaDrive'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('CONNECTION ISSUE'), findsOneWidget);
      expect(
        tester.getTopLeft(find.textContaining('reach NexaDrive')).dy,
        lessThan(280),
      );
      // The empty-folder copy must not appear when the load failed.
      expect(find.text('Your cloud is empty'), findsNothing);
      expect(find.text('This folder is empty'), findsNothing);
    });

    testWidgets('upload offers a gallery choice and a file browser',
        (tester) async {
      await pump(tester, FilesScreen(api: listingApi(const [])));
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      // An empty folder also offers a primary Upload action, so the overflow
      // menu entry is the last of the two labels in the widget tree.
      await tester.tap(find.text('Upload files').last);
      await tester.pumpAndSettle();

      expect(find.text('Choose from gallery'), findsOneWidget);
      expect(find.text('Browse files'), findsOneWidget);
      expect(tester.takeException(), isNull);
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
      // The Files header keeps only Search and a single overflow control;
      // upload, sort and view switching live inside the overflow menu.
      expect(find.byTooltip('Search files'), findsOneWidget);
      expect(find.byTooltip('More actions'), findsOneWidget);
      expect(find.byTooltip('Upload files'), findsNothing);
      expect(find.byTooltip('Sort files'), findsNothing);
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      expect(find.text('Upload files'), findsOneWidget);
      expect(find.text('Sort & filter…'), findsOneWidget);
      expect(find.text('Grid view'), findsOneWidget);
      await tester.tap(find.text('Grid view'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
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

  group('shell navigation keeps each tab alive', () {
    /// Counts listing calls so a tab switch that re-fetches is visible.
    late int fileListings;

    Api shellApi() {
      fileListings = 0;
      return Api(
        session(),
        client: _ShellClient(() => fileListings++),
      );
    }

    Future<void> pumpShell(WidgetTester tester, Api api) async {
      SharedPreferences.setMockInitialValues({});
      // A private, disk-free journal keeps one test's transfers from leaving
      // a strip or notice behind in another test.
      UploadManager.forTesting(
        File('unused-upload-queue.jsonl'),
        bootstrap: false,
        store: _MemoryUploadStore(),
      );
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        NexaDriveApp(
            session: session(),
            prefs: await SharedPreferences.getInstance(),
            api: api),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('returning to My files does not re-list the folder',
        (tester) async {
      final api = shellApi();
      await pumpShell(tester, api);

      // Open My files for the first time: exactly one listing.
      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();
      final afterFirstVisit = fileListings;
      expect(afterFirstVisit, greaterThanOrEqualTo(1));

      // Leave and come back. A shell that rebuilds the page from scratch would
      // fetch again here, losing the folder the user was browsing.
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();

      expect(fileListings, afterFirstVisit);
      expect(tester.takeException(), isNull);
    });

    testWidgets('More opens a compact 3 by 2 menu without replacing the dock',
        (tester) async {
      final api = shellApi();
      await pumpShell(tester, api);

      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();

      expect(find.text('Scan'), findsOneWidget);
      expect(find.text('Transfers'), findsOneWidget);
      expect(find.text('Trash'), findsOneWidget);
      expect(find.text('Sync'), findsOneWidget);
      expect(find.text('Alerts'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      // The compact popup and the pill share the same tonal M3 surface role.
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Material &&
              widget.color == AppColors.lightScheme.surfaceContainerHigh,
        ),
        findsWidgets,
      );
      // The floating navigation remains mounted beneath the menu.
      // The restored Home has a NexaDrive page title, so the pill owns "Home".
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Files'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Escape dismisses the modal More menu', (tester) async {
      final api = shellApi();
      await pumpShell(tester, api);

      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.text('Scan'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('Scan'), findsNothing);
      // The restored Home has a NexaDrive page title, so the pill owns "Home".
      expect(find.text('Home'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('switching tabs closes More and its scrim', (tester) async {
      await pumpShell(tester, shellApi());

      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.text('Scan'), findsOneWidget);
      expect(moreScrim(), findsOneWidget);

      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();

      expect(find.text('Scan'), findsNothing);
      expect(moreScrim(), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a pushed route always closes More, back does not restore it',
        (tester) async {
      await pumpShell(tester, shellApi());

      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(moreScrim(), findsOneWidget);

      // Push directly through the Navigator: even a route the shell did not
      // initiate must not leave the in-shell menu or scrim mounted.
      final navigator = Navigator.of(tester.element(find.byType(AppShell)));
      unawaited(navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Pushed page')),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Pushed page'), findsOneWidget);
      expect(find.text('Scan'), findsNothing);
      expect(moreScrim(), findsNothing);

      navigator.pop();
      await tester.pumpAndSettle();

      expect(find.text('Pushed page'), findsNothing);
      expect(find.text('Scan'), findsNothing);
      expect(moreScrim(), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('upload completion leaves no modal or popup behind',
        (tester) async {
      final api = shellApi();
      await pumpShell(tester, api);
      // A checked-in fixture is visible both to the widget test's fake I/O
      // proxy and to the real I/O zone that reads upload chunks.
      final source = File('test/fixtures/upload_done.txt');

      final shellContext = tester.element(find.byType(AppShell));
      // Both the journal and the file chunk reads are real I/O, so they must
      // run outside the widget test's fake-async zone. Waiting for the manager
      // event avoids racing the background transfer against fake timers.
      await tester.runAsync(() async {
        final completed = UploadManager.current.events
            .firstWhere((event) => event.kind == UploadEventKind.completed)
            .timeout(const Duration(seconds: 10));
        await UploadProgressDialog.showSources(
          shellContext,
          sources: [
            UploadSource(
              path: source.path,
              name: 'done.txt',
              size: 4,
            ),
          ],
          folder: '',
          api: api,
        );
        await completed;
      });
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(
        UploadManager.current.items().single.state,
        UploadState.completed,
        reason: 'the fake server must actually finish the upload',
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(NexaPillNotice), findsNothing);
      // Completion feedback belongs here, and the strip lingers briefly.
      expect(find.byType(ActiveTransferStrip), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        "Home's New folder shortcut opens the folder dialog on My files",
        (tester) async {
      final api = shellApi();
      await pumpShell(tester, api);

      await tester.tap(find.text('New folder'));
      await tester.pumpAndSettle();

      // The action really ran, rather than only switching tabs.
      expect(find.text('Folder name'), findsOneWidget);
      expect(find.text('Create'), findsOneWidget);
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
/// Disk-free journal for widget tests: fake-async zones cannot settle real
/// file I/O, and these tests only need completion feedback, not persistence.
class _MemoryUploadStore extends UploadStore {
  _MemoryUploadStore() : super(File('unused-upload-queue.jsonl'));

  @override
  Future<List<UploadItem>> load() async => const <UploadItem>[];

  @override
  Future<void> append(UploadItem item) async {}

  @override
  Future<void> appendAll(List<UploadItem> items) async {}

  @override
  Future<void> remove(String id) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<void> compact([List<UploadItem>? items]) async {}

  @override
  Future<void> dispose() async {}
}

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

/// Answers every request the signed-in shell makes, so a widget test can drive
/// real navigation. Counts file listing calls through [onListing].
class _ShellClient extends http.BaseClient {
  _ShellClient(this.onListing);
  final void Function() onListing;
  final Map<String, int> _uploadSizes = <String, int>{};
  final Map<String, String> _uploadPaths = <String, String>{};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.StreamedRequest) {
      await request.finalize().drain<void>();
    }
    final path = request.url.path;
    final query = request.url.queryParameters;
    Object body;
    switch (path) {
      case '/api/files':
        onListing();
        body = [
          {
            'name': 'Photos',
            'path': 'Photos',
            'kind': 'folder',
            'size': 0,
            'modified_at': '2026-09-16T10:00:00Z',
          },
        ];
      case '/api/storage':
        body = {'used_bytes': 1024, 'file_count': 3};
      case '/api/server/status':
        body = {
          'version': '1.1.0',
          'api_version': '1.1.0',
          'instance_id': 'test'
        };
      case '/api/uploads/chunk':
        final id = query['upload_id'] ?? '';
        final total = int.tryParse(query['total'] ?? '') ?? 0;
        final folder = query['path'] ?? '';
        final name = query['name'] ?? '';
        final offset = int.tryParse(query['offset'] ?? '') ?? 0;
        final remotePath = folder.isEmpty ? name : '$folder/$name';
        _uploadSizes[id] = total;
        _uploadPaths[id] = remotePath;
        body = offset >= total
            ? {
                'status': 'completed',
                'offset': total,
                'bytes_received': total,
                'path': remotePath,
              }
            : {'status': 'receiving', 'offset': total};
      case '/api/uploads/status':
        final id = query['upload_id'] ?? '';
        final size = _uploadSizes[id];
        body = size == null
            ? {'status': 'unknown', 'bytes_received': 0}
            : {
                'status': 'receiving',
                'bytes_received': size,
                'path': _uploadPaths[id],
              };
      default:
        body = <Object>[];
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
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
