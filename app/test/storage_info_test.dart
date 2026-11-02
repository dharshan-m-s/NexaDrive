import 'package:flutter_test/flutter_test.dart';
import 'package:nexadrive/core/models/file_entry.dart';

void main() {
  group('StorageInfo calculations', () {
    test('calculates used fraction and available bytes from a quota', () {
      final storage = StorageInfo.fromJson({
        'used_bytes': 40,
        'file_count': 7,
        'quota_bytes': 100,
      });
      expect(storage.usageFraction, 0.4);
      expect(storage.freeBytes, 60);
      expect(storage.fileCount, 7);
    });

    test('parses server-calculated composition, activity and size statistics',
        () {
      final storage = StorageInfo.fromJson({
        'used_bytes': 1200,
        'file_count': 3,
        'quota_bytes': 5000,
        'type_breakdown': [
          {
            'key': 'images',
            'label': 'Images',
            'bytes': 800,
            'count': 2,
          },
          {
            'key': 'documents',
            'label': 'Documents',
            'bytes': 400,
            'count': 1,
          },
        ],
        'activity_last_7_days': [
          {
            'date': '2026-11-02',
            'label': 'Mon',
            'bytes': 400,
            'count': 1,
          },
        ],
        'size_distribution': [
          {
            'key': 'under_1mb',
            'label': 'Under 1 MB',
            'count': 3,
            'bytes': 1200,
          },
        ],
        'largest_files': [
          {
            'name': 'portfolio.png',
            'path': 'Design/portfolio.png',
            'size_bytes': 800,
            'modified_at': '2026-11-02T08:00:00Z',
          },
        ],
      });

      expect(storage.typeBreakdown, hasLength(2));
      expect(storage.typeBreakdown.first.key, 'images');
      expect(storage.typeBreakdown.first.bytes, 800);
      expect(storage.activityLast7Days.single.count, 1);
      expect(storage.sizeDistribution.single.label, 'Under 1 MB');
      expect(storage.largestFiles.single.path, 'Design/portfolio.png');
      expect(storage.largestFiles.single.sizeBytes, 800);
    });

    test('clamps usage and free bytes when a quota is exceeded', () {
      final storage = StorageInfo(
        usedBytes: 140,
        fileCount: 2,
        quotaBytes: 100,
      );
      expect(storage.usageFraction, 1);
      expect(storage.freeBytes, 0);
    });

    test('represents a zero-byte quota as a real limit', () {
      final storage = StorageInfo(
        usedBytes: 1,
        fileCount: 1,
        quotaBytes: 0,
      );
      expect(storage.usageFraction, 1);
      expect(storage.freeBytes, 0);
    });

    test('represents unlimited quota without inventing free space', () {
      final storage = StorageInfo(
        usedBytes: 1234,
        fileCount: 1,
      );
      expect(storage.usageFraction, 0);
      expect(storage.freeBytes, 0);
    });
  });
}
