import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nexadrive/core/models/file_entry.dart';
import 'package:nexadrive/ui/widgets/nexa_file_tile.dart';

Uint8List _tinyJpeg() => Uint8List.fromList(
      img.encodeJpg(img.Image(width: 2, height: 2)),
    );

void main() {
  testWidgets(
    'list selection keeps the preview and adds a left-hand select control',
    (tester) async {
      final entry = FileEntry(
        name: 'clip.mp4',
        path: 'clip.mp4',
        type: 'file',
      );
      var toggles = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NexaFileTile(
              entry: entry,
              thumbnail: _tinyJpeg(),
              selecting: true,
              onSelectToggle: () => toggles++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Select clip.mp4'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^clip\.mp4, ')), findsOneWidget);

      await tester.tap(find.byTooltip('Select clip.mp4'));
      await tester.pump();

      expect(toggles, 1);
    },
  );

  for (final name in ['clip.mp4', 'report.pdf']) {
    testWidgets('grid renders a real preview for $name', (tester) async {
      final entry = FileEntry(name: name, path: name, type: 'file');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 120,
                child: SingleChildScrollView(
                  child: NexaFileGridTile(
                    entry: entry,
                    thumbnail: _tinyJpeg(),
                    selecting: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(RegExp('^${RegExp.escape(name)}, ')),
        findsOneWidget,
      );
    });
  }
}
