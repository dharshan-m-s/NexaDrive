import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// One file inside a picked folder.
class FolderFile {
  const FolderFile({
    required this.relativePath,
    required this.name,
    required this.size,
    this.localPath,
    this.sourceUri,
  });

  /// Path of the file relative to the picked folder, using `/` separators.
  final String relativePath;

  /// File name including its extension.
  final String name;

  /// Size in bytes.
  final int size;

  /// Absolute path on desktop platforms, where folders are ordinary
  /// directories.
  final String? localPath;

  /// Android Storage Access Framework document URI. The upload queue streams
  /// from this directly; the file is never copied into the app cache.
  final String? sourceUri;

  /// The value the upload queue stores as its source location.
  String get location => localPath ?? sourceUri ?? '';
}

/// A folder the user picked, ready to be queued.
class FolderSelection {
  const FolderSelection({
    required this.name,
    required this.files,
    this.root,
  });

  /// Name of the picked folder. It becomes the top-level folder on the
  /// server so the upload keeps the shape the user saw.
  final String name;

  /// Every file in the folder, with its relative path.
  final List<FolderFile> files;

  /// Legacy: the temporary directory older Android builds used to
  /// materialise a picked tree into. New selections have no root.
  final String? root;

  /// Total number of bytes in the folder.
  int get totalBytes =>
      files.fold<int>(0, (int sum, FolderFile file) => sum + file.size);

  /// The destination folder for [files] inside the user's storage root.
  String destination(String parent) {
    final base = parent.trim().isEmpty ? name : '$parent/$name';
    return base;
  }
}

/// Picks folders and turns them into uploadable files.
///
/// Desktop platforms can walk a directory directly. Android has no folder
/// path at all — the system picker hands back a tree URI — so the tree is
/// listed and each document URI is queued; bytes are streamed from the
/// provider on demand and never copied into the app cache.
class FolderUploadPicker {
  const FolderUploadPicker();

  static const MethodChannel _channel =
      MethodChannel('nexadrive/folder_picker');

  /// Whether this platform can pick a folder at all.
  static bool get isSupported =>
      Platform.isAndroid ||
      Platform.isLinux ||
      Platform.isWindows ||
      Platform.isMacOS;

  /// Opens the folder picker.
  ///
  /// Returns `null` when the user dismissed the picker.
  Future<FolderSelection?> pick() async {
    if (Platform.isAndroid) return _pickAndroid();
    return _pickDesktop();
  }

  Future<FolderSelection?> _pickDesktop() async {
    final root = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose a folder to upload',
    );
    if (root == null) return null;
    final files = await walkDirectory(root);
    if (files.isEmpty) return null;
    return FolderSelection(name: p.basename(root), files: files);
  }

  Future<FolderSelection?> _pickAndroid() async {
    final uri = await _channel.invokeMethod<String>('pickFolder');
    if (uri == null) return null;
    final payload =
        await _channel.invokeMapMethod<String, dynamic>('listFolder', {
      'uri': uri,
    });
    if (payload == null) return null;
    final rawFiles = (payload['files'] as List<dynamic>? ?? const <dynamic>[]);
    final files = <FolderFile>[];
    for (final raw in rawFiles) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final localPath = map['localPath'] as String?;
      final sourceUri = map['sourceUri'] as String?;
      final location = localPath ?? sourceUri;
      if (location == null || location.isEmpty) continue;
      files.add(FolderFile(
        relativePath: map['path'] as String? ?? '',
        name: map['name'] as String? ?? p.basename(location),
        size: (map['size'] as num?)?.toInt() ?? 0,
        localPath: localPath,
        sourceUri: sourceUri,
      ));
    }
    if (files.isEmpty) return null;
    return FolderSelection(
      name: payload['name'] as String? ?? 'folder',
      files: files,
      root: payload['root'] as String?,
    );
  }

  /// Walks [root] and returns every file below it.
  ///
  /// Symbolic links are not followed: a link that points back into the tree
  /// would otherwise turn the walk into an endless loop.
  static Future<List<FolderFile>> walkDirectory(String root) async {
    final files = <FolderFile>[];
    final stack = <String>[root];
    while (stack.isNotEmpty) {
      final directory = stack.removeLast();
      List<FileSystemEntity> children;
      try {
        children = await Directory(directory).list(followLinks: false).toList();
      } catch (_) {
        continue;
      }
      for (final child in children) {
        final name = p.basename(child.path);
        if (name.startsWith('.')) continue;
        if (child is Link) continue;
        if (child is Directory) {
          stack.add(child.path);
          continue;
        }
        if (child is! File) continue;
        int size;
        try {
          size = await child.length();
        } catch (_) {
          continue;
        }
        files.add(FolderFile(
          relativePath:
              p.relative(child.path, from: root).replaceAll('\\', '/'),
          name: name,
          size: size,
          localPath: child.path,
        ));
      }
    }
    return files;
  }
}
