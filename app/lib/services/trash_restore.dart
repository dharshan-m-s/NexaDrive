import 'api.dart';

/// Restores recently trashed paths by resolving their server trash ids.
///
/// The batch delete endpoint returns original paths, while the restore endpoint
/// needs opaque trash ids. Keeping that translation in one place makes undo
/// behavior identical in My files, Photos and Trash.
abstract final class TrashRestore {
  static Future<void> paths(
    Api api,
    Iterable<String> paths, {
    bool Function(String path)? include,
  }) async {
    final wanted = paths.toSet();
    if (wanted.isEmpty) return;
    final rows = await api.trash();
    final ids = <String>[];
    for (final row in rows) {
      final original = row['original_path']?.toString();
      final id = row['id']?.toString();
      if (original == null || id == null || !wanted.contains(original)) {
        continue;
      }
      if (include != null && !include(original)) continue;
      ids.add(id);
    }
    if (ids.isEmpty) {
      throw StateError('Those items are no longer in Trash.');
    }
    final failures = <String>[];
    for (final id in ids) {
      try {
        await api.restoreTrash(id);
      } catch (_) {
        failures.add(id);
      }
    }
    if (failures.isNotEmpty) {
      throw StateError(
        failures.length == 1
            ? 'One item could not be restored. It may already be back in its folder.'
            : '${failures.length} items could not be restored. They may already be back in their folders.',
      );
    }
  }
}
