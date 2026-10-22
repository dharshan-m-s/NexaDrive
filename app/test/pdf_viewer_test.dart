import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexadrive/core/models/file_entry.dart';
import 'package:nexadrive/services/api.dart';
import 'package:nexadrive/services/session.dart';
import 'package:nexadrive/ui/screens/viewers/pdf_viewer_screen.dart';
import 'package:pdfx/pdfx.dart';

/// Regression coverage for the PDF viewer's resource handling.
///
/// The viewer used to open a native pdfium document and build a
/// `PdfControllerPinch` inside `build()`, so every frame leaked another
/// document/controller and nothing was ever disposed. It also downloaded the
/// whole file before discovering the platform could not render it.
void main() {
  testWidgets('an unsupported platform degrades without downloading the PDF',
      (tester) async {
    // On a host with a native pdfium backend this screen follows the render
    // path, which needs the plugin; the assertions below are Linux/CI.
    if (await hasPdfSupport()) return;

    var downloads = 0;
    final session = Session()
      ..serverUrl = 'https://cloud.example.test'
      ..username = 'tester'
      ..token = 'test-token';
    final api = Api(
      session,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/api/files/download')) downloads++;
        return http.Response.bytes(
          List<int>.filled(8, 0),
          200,
          headers: {'content-type': 'application/pdf'},
        );
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PdfViewerScreen(
          file: FileEntry.fromJson({
            'name': 'doc.pdf',
            'path': 'Docs/doc.pdf',
            'type': 'file',
            'size': 8,
            'modified_at': '2026-09-16T10:00:00Z',
          }),
          api: api,
        ),
      ),
    );
    // Let the async support probe complete.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(
      find.text('PDF reader coming to this device'),
      findsOneWidget,
      reason: 'the unsupported state must be shown, not a blank screen',
    );
    expect(
      downloads,
      0,
      reason: 'support is probed before the file is pulled into memory',
    );
    expect(tester.takeException(), isNull);
  });
}
