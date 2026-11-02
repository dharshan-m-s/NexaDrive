import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexadrive/core/design/app_theme.dart';
import 'package:nexadrive/services/api.dart';
import 'package:nexadrive/services/session.dart';
import 'package:nexadrive/ui/screens/home/storage_insights_screen.dart';

void main() {
  const sizes = <String, Size>{
    'phone': Size(390, 844),
    'short window': Size(800, 480),
    'tablet': Size(900, 1180),
    'desktop': Size(1440, 900),
    'wide desktop': Size(1920, 1080),
  };

  for (final theme in <String, ThemeData>{
    'light': AppTheme.light(),
    'dark': AppTheme.dark(),
  }.entries) {
    group('Storage Insights layout (${theme.key})', () {
      for (final size in sizes.entries) {
        testWidgets('holds on ${size.key}', (tester) async {
          await tester.binding.setSurfaceSize(size.value);
          addTearDown(() => tester.binding.setSurfaceSize(null));

          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme.value,
              home: StorageInsightsScreen(api: _InsightsApi()),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 900));

          expect(find.text('Storage insights'), findsOneWidget);
          expect(find.text('Storage composition'), findsOneWidget);
          expect(find.text('File activity'), findsOneWidget);
          expect(find.text('File size distribution'), findsOneWidget);
          expect(find.text('Largest files'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    });
  }
}

class _InsightsApi extends Api {
  _InsightsApi() : super(_session());

  static Session _session() {
    final session = Session();
    session.serverUrl = 'https://example.com';
    session.token = 'test-token';
    session.username = 'tester';
    session.userId = '1';
    return session;
  }

  @override
  Future<Map<String, dynamic>> storageInsights() async => {
        'used_bytes': 128 * 1024 * 1024,
        'file_count': 24,
        'quota_bytes': 512 * 1024 * 1024,
        'type_breakdown': [
          {
            'key': 'images',
            'label': 'Images',
            'bytes': 3 * 1024 * 1024,
            'count': 9
          },
          {
            'key': 'videos',
            'label': 'Videos',
            'bytes': 96 * 1024 * 1024,
            'count': 3
          },
          {
            'key': 'audio',
            'label': 'Audio',
            'bytes': 8 * 1024 * 1024,
            'count': 4
          },
          {
            'key': 'documents',
            'label': 'Documents',
            'bytes': 4 * 1024 * 1024,
            'count': 5
          },
          {
            'key': 'archives',
            'label': 'Archives',
            'bytes': 12 * 1024 * 1024,
            'count': 1
          },
          {
            'key': 'other',
            'label': 'Other',
            'bytes': 5 * 1024 * 1024,
            'count': 2
          },
        ],
        'activity_last_7_days': [
          for (var i = 0; i < 7; i++)
            {
              'date': [
                '2026-10-27',
                '2026-10-28',
                '2026-10-29',
                '2026-10-30',
                '2026-10-31',
                '2026-11-01',
                '2026-11-02'
              ][i],
              'label': ['Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun', 'Mon'][i],
              'bytes': (i + 1) * 128 * 1024,
              'count': i + 1,
            },
        ],
        'size_distribution': [
          {
            'key': 'under_1mb',
            'label': 'Under 1 MB',
            'count': 12,
            'bytes': 512 * 1024
          },
          {
            'key': '1_to_10mb',
            'label': '1–10 MB',
            'count': 8,
            'bytes': 12 * 1024 * 1024
          },
          {
            'key': '10_to_100mb',
            'label': '10–100 MB',
            'count': 3,
            'bytes': 15 * 1024 * 1024
          },
          {
            'key': 'over_100mb',
            'label': '100 MB and above',
            'count': 1,
            'bytes': 100 * 1024 * 1024 + 512 * 1024
          },
        ],
        'largest_files': [
          for (var i = 0; i < 5; i++)
            {
              'name': 'large-file-$i.mp4',
              'path': 'Media/large-file-$i.mp4',
              'size_bytes': [
                100 * 1024 * 1024 + 512 * 1024,
                9 * 1024 * 1024,
                7 * 1024 * 1024,
                6 * 1024 * 1024,
                5 * 1024 * 1024
              ][i],
              'modified_at': '2026-11-02T08:00:00Z',
            },
        ],
      };
}
