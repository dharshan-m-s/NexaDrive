import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexadrive/core/design/app_theme.dart';
import 'package:nexadrive/core/models/file_entry.dart';
import 'package:nexadrive/services/api.dart';
import 'package:nexadrive/services/session.dart';
import 'package:nexadrive/ui/screens/admin/audit_log_screen.dart';
import 'package:nexadrive/ui/screens/notifications/notifications_screen.dart';
import 'package:nexadrive/ui/screens/trash/trash_screen.dart';
import 'package:nexadrive/ui/screens/viewers/text_viewer_screen.dart';
import 'package:nexadrive/ui/widgets/one_ui_controls.dart';
import 'package:nexadrive/ui/widgets/one_ui_page.dart';

/// Real-layout QA sweep for the page shell and the screens migrated onto it.
///
/// Every screen now builds its page through `OneUiPage`, so a fault in the
/// shell surfaces on all of them at once. This pumps the shell directly with
/// deliberately hostile content — a title that cannot wrap, a subtitle that
/// cannot wrap, a leading control and a trailing action competing for width,
/// and a pinned bottom bar — at every window size in both themes.
///
/// The migrated screens are pumped too, so their own rows and empty states are
/// exercised rather than assumed.
///
/// This runs through the real layout pipeline rather than goldens, because CI
/// cannot reproduce bit-exact pixels; any overflow, unconstrained-flex error,
/// layout exception or paint exception fails the run.
void main() {
  final sizes = <String, Size>{
    'narrow (500x600)': const Size(500, 600),
    'short (800x480)': const Size(800, 480),
    'standard (1280x800)': const Size(1280, 800),
    'wide (1920x1080)': const Size(1920, 1080),
    'very wide (2560x1440)': const Size(2560, 1440),
  };

  for (final themeEntry in {
    'light': AppTheme.light(),
    'dark': AppTheme.dark(),
  }.entries) {
    group('page shell layout QA (${themeEntry.key})', () {
      for (final sizeEntry in sizes.entries) {
        testWidgets('worst-case header holds at ${sizeEntry.key}',
            (tester) async {
          await tester.binding.setSurfaceSize(sizeEntry.value);
          addTearDown(() => tester.binding.setSurfaceSize(null));

          // A single unbroken token cannot wrap, and both controls are present,
          // so this is the tightest row the viewing area can be asked to lay
          // out. It must ellipsize rather than overflow.
          await tester.pumpWidget(_host(
            themeEntry.value,
            OneUiPage(
              title: 'AVeryLongUnbreakableDirectoryNameThatCannotWrapAtAll',
              subtitle:
                  'an equally unbreakable subtitle that also refuses to wrap onto a second line',
              leading: const OneUiBackButton(),
              headerAction: IconButton(
                onPressed: () {},
                icon: const Icon(Icons.refresh_rounded),
              ),
              body: const SizedBox.shrink(),
            ),
          ));
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: 'viewing area must not overflow at ${sizeEntry.key}');
        });

        testWidgets('pinned bottom bar holds at ${sizeEntry.key}',
            (tester) async {
          await tester.binding.setSurfaceSize(sizeEntry.value);
          addTearDown(() => tester.binding.setSurfaceSize(null));

          await tester.pumpWidget(_host(
            themeEntry.value,
            OneUiPage(
              title: 'Transfers',
              bottomBar: FilledButton(
                onPressed: () {},
                child: const Text('Save as PDF'),
              ),
              body: const SizedBox.shrink(),
            ),
          ));
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: 'bottom bar must not overflow at ${sizeEntry.key}');
        });

        testWidgets('headerless immersive page holds at ${sizeEntry.key}',
            (tester) async {
          await tester.binding.setSurfaceSize(sizeEntry.value);
          addTearDown(() => tester.binding.setSurfaceSize(null));

          await tester.pumpWidget(_host(
            themeEntry.value,
            const OneUiPage(
              title: 'Player',
              showHeader: false,
              padding: EdgeInsets.zero,
              body: ColoredBox(color: Colors.black),
            ),
          ));
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: 'headerless page must not overflow at ${sizeEntry.key}');
        });

        testWidgets('scrollable tall body holds at ${sizeEntry.key}',
            (tester) async {
          await tester.binding.setSurfaceSize(sizeEntry.value);
          addTearDown(() => tester.binding.setSurfaceSize(null));

          await tester.pumpWidget(_host(
            themeEntry.value,
            OneUiPage(
              title: 'Log',
              scrollable: true,
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < 200; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('row $i'),
                    ),
                ],
              ),
            ),
          ));
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: 'scrollable body must not overflow at ${sizeEntry.key}');
        });
      }
    });

    group('migrated screens layout QA (${themeEntry.key})', () {
      for (final sizeEntry in sizes.entries) {
        testWidgets('audit log holds at ${sizeEntry.key}', (tester) async {
          await tester.binding.setSurfaceSize(sizeEntry.value);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
              _host(themeEntry.value, AuditLogScreen(api: _FakeApi())));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 120));
          expect(tester.takeException(), isNull,
              reason: 'audit log must not overflow at ${sizeEntry.key}');
        });

        testWidgets('trash holds at ${sizeEntry.key}', (tester) async {
          await tester.binding.setSurfaceSize(sizeEntry.value);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
              _host(themeEntry.value, TrashScreen(api: _FakeApi())));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 120));
          expect(tester.takeException(), isNull,
              reason: 'trash must not overflow at ${sizeEntry.key}');
        });

        testWidgets('notifications holds at ${sizeEntry.key}', (tester) async {
          await tester.binding.setSurfaceSize(sizeEntry.value);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
              _host(themeEntry.value, NotificationsScreen(api: _FakeApi())));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 120));
          expect(tester.takeException(), isNull,
              reason: 'notifications must not overflow at ${sizeEntry.key}');
        });

        testWidgets('text viewer holds at ${sizeEntry.key}', (tester) async {
          await tester.binding.setSurfaceSize(sizeEntry.value);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(_host(
            themeEntry.value,
            TextViewerScreen(api: _FakeApi(), file: _file),
          ));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 120));
          expect(tester.takeException(), isNull,
              reason: 'text viewer must not overflow at ${sizeEntry.key}');
        });
      }
    });
  }
}

Widget _host(ThemeData theme, Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: child,
    );

const _file = FileEntry(
  path: '/notes/readme.md',
  name: 'readme.md',
  size: 2048,
  type: 'file',
);

/// Serves one item per list so the migrated rows are actually laid out rather
/// than only their empty states being checked.
class _FakeApi extends Api {
  _FakeApi() : super(_session());

  static Session _session() {
    final session = Session();
    session.serverUrl = 'https://example.com';
    session.token = 'tok';
    session.username = 'ada';
    session.userId = '1';
    return session;
  }

  @override
  Future<List<Map<String, dynamic>>> audit({int limit = 200}) async => [
        for (var i = 0; i < 12; i++)
          {
            'id': '$i',
            'username': 'ada',
            'action': 'write',
            'path': '/a/very/deeply/nested/path/that/is/long/file-$i.txt',
            'created_at': DateTime(2026, 9, 26, 12, i).toIso8601String(),
          },
      ];

  @override
  Future<List<Map<String, dynamic>>> trash() async => [
        for (var i = 0; i < 12; i++)
          {
            'id': '$i',
            'name': 'deleted-file-with-a-long-name-$i.txt',
            'size': 4096,
            'kind': 'file',
            'deleted_at': DateTime(2026, 9, 26, 12, i).toIso8601String(),
          },
      ];

  @override
  Future<List<Map<String, dynamic>>> notifications({
    bool unreadOnly = false,
  }) async =>
      [
        for (var i = 0; i < 12; i++)
          {
            'id': '$i',
            'kind': 'backup_completed',
            'title': 'Backup $i completed with a rather long headline',
            'message': 'The nightly backup finished and everything reconciled.',
            'read': i.isEven,
            'created_at': DateTime(2026, 9, 26, 12, i).toIso8601String(),
          },
      ];

  @override
  Future<Uint8List> download(String path) async =>
      Uint8List.fromList('hello\nworld\n'.codeUnits);
}
