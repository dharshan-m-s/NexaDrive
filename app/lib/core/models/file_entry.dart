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

  DateTime? get modified => modifiedAt == null ? null : DateTime.tryParse(modifiedAt!);

  /// The entry kind from raw API JSON. The server historically serialized
  /// this as `kind`; clients made it `type`. Accept both so old and new server
  /// builds behave identically.
  static String kindOf(Map<String, dynamic> j) =>
      (j['type'] ?? j['kind'] ?? 'file').toString();

  factory FileEntry.fromJson(Map<String, dynamic> j) => FileEntry(
        name: j['name']?.toString() ?? (j['path']?.toString() ?? '').split('/').last,
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

/// Storage usage response.
class StorageInfo {
  final int usedBytes;
  final int fileCount;
  final int? quotaBytes;

  const StorageInfo({required this.usedBytes, required this.fileCount, this.quotaBytes});

  int get fileCountSafe => fileCount;
  int get quotaOrZero => quotaBytes ?? 0;
  double get usageFraction {
    final q = quotaBytes;
    if (q == null || q <= 0) return 0;
    return (usedBytes / q).clamp(0.0, 1.0).toDouble();
  }

  int get freeBytes {
    final q = quotaBytes;
    if (q == null) return 0;
    final free = q - usedBytes;
    return free.clamp(0, q).toInt();
  }

  factory StorageInfo.fromJson(Map<String, dynamic> j) => StorageInfo(
        usedBytes: (j['used_bytes'] as num?)?.toInt() ?? 0,
        fileCount: (j['file_count'] as num?)?.toInt() ?? 0,
        quotaBytes: (j['quota_bytes'] as num?)?.toInt(),
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