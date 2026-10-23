import 'dart:convert';

/// Lifecycle of a single queued upload.
///
/// The queue is file-backed and survives an app restart, so the state has to
/// be explicit about what may still be resumed and what is finished.
enum UploadState {
  /// Waiting for a free worker slot.
  queued,

  /// A chunk request is in flight.
  uploading,

  /// Held back by the user. The server session stays alive so the transfer
  /// continues from the byte it reached.
  paused,

  /// A transient failure happened and the next attempt is scheduled.
  retrying,

  /// Stored on the server.
  completed,

  /// Gave up. The reason is in [UploadItem.error].
  failed,

  /// Cancelled by the user. The server session was released.
  cancelled;

  /// Whether the upload will not change state on its own any more.
  bool get isTerminal =>
      this == UploadState.completed ||
      this == UploadState.failed ||
      this == UploadState.cancelled;

  /// Whether the upload still owes bytes to the server.
  bool get isPending => !isTerminal;

  /// The wire form used in the on-disk journal.
  String get wire => name;

  static UploadState parse(String? raw) {
    for (final state in UploadState.values) {
      if (state.name == raw) return state;
    }
    return UploadState.queued;
  }
}

/// One file on its way to the server.
///
/// The item is the unit of both persistence and UI: the journal stores whole
/// snapshots, and the Transfers screen renders one row per item.
class UploadItem {
  /// Stable id. Doubles as the server-side `upload_id`, so a resumed
  /// transfer keeps its session.
  final String id;

  /// Absolute path of the local file that is being uploaded, or the Android
  /// document URI when [sourceUri] is set.
  final String localPath;

  /// Android Storage Access Framework URI for a folder-upload file.
  ///
  /// When set, bytes are streamed directly from the provider with
  /// [ContentSource] and no copy is made in app storage.
  final String? sourceUri;

  /// File name as it should appear on the server.
  final String name;

  /// Destination folder inside the user's storage root.
  final String folder;

  /// Total size of the local file in bytes.
  final int size;

  /// How many bytes the server has confirmed.
  final int transferred;

  /// Where the transfer currently is.
  final UploadState state;

  /// Why the transfer failed, when it did.
  final String? error;

  /// How many consecutive attempts have failed.
  final int attempts;

  /// Whether [localPath] points into a temporary directory that the app owns
  /// and may delete (a legacy copied Android document). New folder picks
  /// stream from their document URI instead.
  final bool temporarySource;

  final DateTime createdAt;
  final DateTime updatedAt;

  const UploadItem({
    required this.id,
    required this.localPath,
    this.sourceUri,
    required this.name,
    required this.folder,
    required this.size,
    required this.transferred,
    required this.state,
    required this.error,
    required this.attempts,
    required this.temporarySource,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Fraction of the file the server has confirmed, in `0..1`.
  double get progress {
    if (size <= 0) return state == UploadState.completed ? 1 : 0;
    return (transferred / size).clamp(0.0, 1.0);
  }

  /// A copy with the given fields replaced.
  ///
  /// [error] is only cleared when [clearError] is set, so a copy never
  /// silently keeps a stale failure message.
  UploadItem copyWith({
    String? localPath,
    String? sourceUri,
    String? name,
    String? folder,
    int? size,
    int? transferred,
    UploadState? state,
    String? error,
    bool clearError = false,
    int? attempts,
    bool? temporarySource,
    DateTime? updatedAt,
  }) {
    return UploadItem(
      id: id,
      localPath: localPath ?? this.localPath,
      sourceUri: sourceUri ?? this.sourceUri,
      name: name ?? this.name,
      folder: folder ?? this.folder,
      size: size ?? this.size,
      transferred: transferred ?? this.transferred,
      state: state ?? this.state,
      error: clearError ? null : (error ?? this.error),
      attempts: attempts ?? this.attempts,
      temporarySource: temporarySource ?? this.temporarySource,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'localPath': localPath,
        if (sourceUri != null) 'sourceUri': sourceUri,
        'name': name,
        'folder': folder,
        'size': size,
        'transferred': transferred,
        'state': state.wire,
        'error': error,
        'attempts': attempts,
        'temporarySource': temporarySource,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory UploadItem.fromJson(Map<String, dynamic> json) => UploadItem(
        id: json['id'] as String,
        localPath: json['localPath'] as String? ?? '',
        sourceUri: json['sourceUri'] as String?,
        name: json['name'] as String? ?? '',
        folder: json['folder'] as String? ?? '',
        size: (json['size'] as num?)?.toInt() ?? 0,
        transferred: (json['transferred'] as num?)?.toInt() ?? 0,
        state: UploadState.parse(json['state'] as String?),
        error: json['error'] as String?,
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        temporarySource: json['temporarySource'] as bool? ?? false,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
      );

  /// The journal line for this item.
  String encode() => jsonEncode({'id': id, 'item': toJson()});
}
