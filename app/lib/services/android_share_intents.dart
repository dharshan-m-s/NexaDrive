import 'dart:io';

import 'package:flutter/services.dart';

/// One file handed to NexaDrive through Android's system Sharesheet.
class AndroidSharedFile {
  final String uri;
  final String name;
  final String mimeType;
  final int size;
  final String? localPath;
  final String? stageError;

  const AndroidSharedFile({
    required this.uri,
    required this.name,
    required this.mimeType,
    required this.size,
    this.localPath,
    this.stageError,
  });

  factory AndroidSharedFile.fromMap(Map<String, dynamic> map) {
    return AndroidSharedFile(
      uri: map['uri']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Shared file',
      mimeType: map['mimeType']?.toString() ?? 'application/octet-stream',
      size: (map['size'] as num?)?.toInt() ?? -1,
      localPath: map['localPath']?.toString(),
      stageError: map['stageError']?.toString(),
    );
  }

  Map<String, Object?> toMap() => {
        'uri': uri,
        'name': name,
        'mimeType': mimeType,
        'size': size,
      };

  AndroidSharedFile withStageError(String error) => AndroidSharedFile(
        uri: uri,
        name: name,
        mimeType: mimeType,
        size: size,
        localPath: localPath,
        stageError: error,
      );
}

/// Bridges single and multiple Android share intents into Flutter.
class AndroidShareIntents {
  AndroidShareIntents._();

  static const MethodChannel _channel =
      MethodChannel('nexadrive/share_intents');

  static Future<void> initialize(
    ValueChanged<List<AndroidSharedFile>> onFiles,
  ) async {
    if (!Platform.isAndroid) return;

    Future<void> deliver(Object? raw) async {
      final files = _parse(raw);
      if (files.isEmpty) return;
      try {
        final staged = await stage(files);
        if (staged.isNotEmpty) onFiles(staged);
      } catch (error) {
        onFiles(files
            .map((file) => file.withStageError(error.toString()))
            .toList(growable: false));
      }
    }

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedFiles') await deliver(call.arguments);
    });

    try {
      final pending = await _channel.invokeMethod<List<dynamic>>(
        'consumePendingSharedFiles',
      );
      await deliver(pending);
    } on PlatformException {
      // Older platform builds remain usable without the optional bridge.
    } on MissingPluginException {
      // Non-Android and stale host builds simply have no share target.
    }
  }

  /// Copies incoming content URIs into app-private storage on Android. This
  /// turns temporary Sharesheet grants into durable local upload sources and
  /// determines the true size even when a provider omits metadata.
  static Future<List<AndroidSharedFile>> stage(
    List<AndroidSharedFile> files,
  ) async {
    if (!Platform.isAndroid || files.isEmpty) return files;
    final staged = await _channel.invokeMethod<List<dynamic>>(
      'stageSharedFiles',
      files.map((file) => file.toMap()).toList(growable: false),
    );
    return _parse(staged);
  }

  /// Acknowledges only after the files have entered the durable upload queue.
  /// Dismissed imports remain pending and can be reviewed again.
  static Future<void> acknowledge(List<AndroidSharedFile> files) async {
    if (!Platform.isAndroid || files.isEmpty) return;
    await _channel.invokeMethod<void>(
      'acknowledgeSharedFiles',
      files.map((file) => file.uri).toList(growable: false),
    );
  }

  static List<AndroidSharedFile> _parse(Object? raw) {
    if (raw is! List) return const [];
    final files = <AndroidSharedFile>[];
    final seen = <String>{};
    for (final value in raw) {
      if (value is! Map) continue;
      final file = AndroidSharedFile.fromMap(
        Map<String, dynamic>.from(value),
      );
      if (file.uri.isEmpty || !seen.add(file.uri)) continue;
      files.add(file);
    }
    return files;
  }

  static void dispose() {
    if (Platform.isAndroid) _channel.setMethodCallHandler(null);
  }
}
