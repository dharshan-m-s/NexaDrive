import '../../core/utils/file_kind.dart';

/// A file or folder entry returned by the NexaDrive API.
class FileEntry {
  final String name;
  final String path;
  final String type; // 'file' | 'folder'
  final int? size;
  final String? modifiedAt;
  final bool? pinned;
  final bool? offlineAvailable;

  const FileEntry({
    required this.name,
    required this.path,
    required this.type,
    this.size,
    this.modifiedAt,
    this.pinned,
    this.offlineAvailable,
  });

  bool get isFolder => type == 'folder';

  Category get category => FileKind.category(name: name, type: type);

  DateTime? get modified =>
      modifiedAt == null ? null : DateTime.tryParse(modifiedAt!);

  /// The entry kind from raw API JSON. The server historically serialized
  /// this as `kind`; clients made it `type`. Accept both so old and new server
  /// builds behave identically.
  static String kindOf(Map<String, dynamic> j) =>
      (j['type'] ?? j['kind'] ?? 'file').toString();

  factory FileEntry.fromJson(Map<String, dynamic> j) => FileEntry(
        name: j['name']?.toString() ??
            (j['path']?.toString() ?? '').split('/').last,
        path: j['path']?.toString() ?? '',
        type: kindOf(j),
        size: (j['size'] as num?)?.toInt(),
        modifiedAt: j['modified_at']?.toString(),
        pinned: j['pinned'] as bool?,
        offlineAvailable: j['offline_available'] as bool?,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'type': type,
        if (size != null) 'size': size,
        if (modifiedAt != null) 'modified_at': modifiedAt,
        if (pinned != null) 'pinned': pinned,
        if (offlineAvailable != null) 'offline_available': offlineAvailable,
      };
}

/// One real file-type bucket returned by the server's filesystem walk.
class StorageTypeStat {
  final String key;
  final String label;
  final int bytes;
  final int count;

  const StorageTypeStat({
    required this.key,
    required this.label,
    required this.bytes,
    required this.count,
  });

  factory StorageTypeStat.fromJson(Map<String, dynamic> json) =>
      StorageTypeStat(
        key: json['key']?.toString() ?? 'other',
        label: json['label']?.toString() ?? 'Other',
        bytes: (json['bytes'] as num?)?.toInt() ?? 0,
        count: (json['count'] as num?)?.toInt() ?? 0,
      );
}

/// A UTC calendar-day bucket of files modified during the last seven days.
class StorageDayStat {
  final String date;
  final String label;
  final int bytes;
  final int count;

  const StorageDayStat({
    required this.date,
    required this.label,
    required this.bytes,
    required this.count,
  });

  factory StorageDayStat.fromJson(Map<String, dynamic> json) => StorageDayStat(
        date: json['date']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        bytes: (json['bytes'] as num?)?.toInt() ?? 0,
        count: (json['count'] as num?)?.toInt() ?? 0,
      );
}

/// File-count and byte totals grouped by server-computed size ranges.
class StorageSizeBand {
  final String key;
  final String label;
  final int count;
  final int bytes;

  const StorageSizeBand({
    required this.key,
    required this.label,
    required this.count,
    required this.bytes,
  });

  factory StorageSizeBand.fromJson(Map<String, dynamic> json) =>
      StorageSizeBand(
        key: json['key']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        count: (json['count'] as num?)?.toInt() ?? 0,
        bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      );
}

/// A real largest-file result. Paths remain server-relative.
class StorageLargestFile {
  final String name;
  final String path;
  final int sizeBytes;
  final DateTime? modifiedAt;

  const StorageLargestFile({
    required this.name,
    required this.path,
    required this.sizeBytes,
    this.modifiedAt,
  });

  factory StorageLargestFile.fromJson(Map<String, dynamic> json) =>
      StorageLargestFile(
        name: json['name']?.toString() ?? '',
        path: json['path']?.toString() ?? '',
        sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
        modifiedAt: DateTime.tryParse(json['modified_at']?.toString() ?? ''),
      );
}

/// Storage usage and live filesystem statistics returned by /api/storage.
class StorageInfo {
  final int usedBytes;
  final int fileCount;
  final int? quotaBytes;
  final List<StorageTypeStat> typeBreakdown;
  final List<StorageDayStat> activityLast7Days;
  final List<StorageSizeBand> sizeDistribution;
  final List<StorageLargestFile> largestFiles;

  const StorageInfo({
    required this.usedBytes,
    required this.fileCount,
    this.quotaBytes,
    this.typeBreakdown = const [],
    this.activityLast7Days = const [],
    this.sizeDistribution = const [],
    this.largestFiles = const [],
  });

  int get fileCountSafe => fileCount;
  int get quotaOrZero => quotaBytes ?? 0;
  double get usageFraction {
    final q = quotaBytes;
    if (q == null) return 0;
    if (q == 0) return usedBytes > 0 ? 1 : 0;
    return (usedBytes / q).clamp(0.0, 1.0).toDouble();
  }

  int get freeBytes {
    final q = quotaBytes;
    if (q == null) return 0;
    final free = q - usedBytes;
    return free.clamp(0, q).toInt();
  }

  factory StorageInfo.fromJson(Map<String, dynamic> json) => StorageInfo(
        usedBytes: (json['used_bytes'] as num?)?.toInt() ?? 0,
        fileCount: (json['file_count'] as num?)?.toInt() ?? 0,
        quotaBytes: (json['quota_bytes'] as num?)?.toInt(),
        typeBreakdown: (json['type_breakdown'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((item) => StorageTypeStat.fromJson(
                  Map<String, dynamic>.from(item),
                ))
            .toList(growable: false),
        activityLast7Days:
            (json['activity_last_7_days'] as List<dynamic>? ?? const [])
                .whereType<Map>()
                .map((item) => StorageDayStat.fromJson(
                      Map<String, dynamic>.from(item),
                    ))
                .toList(growable: false),
        sizeDistribution:
            (json['size_distribution'] as List<dynamic>? ?? const [])
                .whereType<Map>()
                .map((item) => StorageSizeBand.fromJson(
                      Map<String, dynamic>.from(item),
                    ))
                .toList(growable: false),
        largestFiles: (json['largest_files'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((item) => StorageLargestFile.fromJson(
                  Map<String, dynamic>.from(item),
                ))
            .toList(growable: false),
      );
}

/// Server status response.
class ServerStatus {
  final String instanceId;
  final DateTime? startedAt;
  final String status;

  const ServerStatus({
    required this.instanceId,
    required this.startedAt,
    required this.status,
  });

  factory ServerStatus.fromJson(Map<String, dynamic> j) => ServerStatus(
        instanceId: j['instance_id']?.toString() ?? '',
        startedAt: DateTime.tryParse(j['started_at']?.toString() ?? ''),
        status: j['status']?.toString() ?? 'unknown',
      );
}
