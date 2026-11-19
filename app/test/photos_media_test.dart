import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexadrive/core/design/app_theme.dart';
import 'package:nexadrive/services/api.dart';
import 'package:nexadrive/services/session.dart';
import 'package:nexadrive/ui/screens/media/video_player_screen.dart';
import 'package:nexadrive/ui/screens/photos/photo_viewer.dart';
import 'package:nexadrive/ui/screens/photos/photos_screen.dart';
import 'package:nexadrive/ui/screens/viewers/pdf_viewer_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MediaApi api;
  late Session session;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = _MediaApi();
    session = Session()
      ..serverUrl = 'https://example.com'
      ..token = 'tok'
      ..username = 'ada'
      ..userId = '1';
  });

  Future<void> pumpPhotos(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: PhotosScreen(api: api, session: session)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the gallery includes videos and PDFs from the file tree',
      (tester) async {
    await pumpPhotos(tester);

    expect(find.text('No media yet'), findsNothing);
    expect(find.text('VIDEO'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
    expect(find.byTooltip('Gallery options'), findsOneWidget);
    expect(find.byTooltip('Change grid density'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('videos and PDFs use the existing viewers', (tester) async {
    await pumpPhotos(tester);

    await tester.tap(find.text('VIDEO'));
    await tester.pumpAndSettle();
    expect(find.byType(VideoPlayerScreen), findsOneWidget);
    expect(find.byType(PhotoViewer), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('PDF'));
    await tester.pumpAndSettle();
    expect(find.byType(PdfViewerScreen), findsOneWidget);
    expect(find.byType(PhotoViewer), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('select all asks for confirmation before deleting',
      (tester) async {
    await pumpPhotos(tester);

    await tester.longPress(find.text('VIDEO'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Select all'));
    await tester.pumpAndSettle();
    expect(find.text('2 items'), findsWidgets);

    await tester.tap(find.byTooltip('Move selected items to Trash'));
    await tester.pumpAndSettle();
    expect(find.text('Move to Trash'), findsOneWidget);
    expect(find.text('Move 2 items to trash?'), findsOneWidget);

    // Cancelling keeps every file and performs no destructive request.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.deletedPaths, isNull);
    expect(find.text('VIDEO'), findsOneWidget);

    await tester.tap(find.byTooltip('Move selected items to Trash'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trash'));
    await tester.pumpAndSettle();

    expect(api.deletedPaths, isNotNull);
    expect(api.deletedPaths,
        containsAll(<String>['Videos/Drive.mp4', 'Docs/Guide.pdf']));
    expect(tester.takeException(), isNull);
  });
}

class _MediaApi extends Api {
  _MediaApi() : super(_session());

  List<String>? deletedPaths;

  static Session _session() => Session()
    ..serverUrl = 'https://example.com'
    ..token = 'tok'
    ..username = 'ada'
    ..userId = '1';

  @override
  Future<List<Map<String, dynamic>>> photos() async => const [];

  @override
  Future<List<Map<String, dynamic>>> listFiles(String path) async {
    switch (path) {
      case '':
        return [
          {
            'name': 'Videos',
            'path': 'Videos',
            'kind': 'folder',
            'size': 0,
          },
          {
            'name': 'Docs',
            'path': 'Docs',
            'kind': 'folder',
            'size': 0,
          },
        ];
      case 'Videos':
        return [
          {
            'name': 'Drive.mp4',
            'path': 'Videos/Drive.mp4',
            'kind': 'file',
            'size': 2048,
            'modified_at': '2026-11-20T10:00:00Z',
          },
        ];
      case 'Docs':
        return [
          {
            'name': 'Guide.pdf',
            'path': 'Docs/Guide.pdf',
            'kind': 'file',
            'size': 1024,
            'modified_at': '2026-11-19T10:00:00Z',
          },
        ];
      default:
        return const [];
    }
  }

  @override
  Future<List<String>> batch({
    required String action,
    required List<String> paths,
    String? destination,
  }) async {
    if (action == 'delete') deletedPaths = List<String>.of(paths);
    return paths;
  }
}
