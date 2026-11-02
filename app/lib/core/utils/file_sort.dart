import '../models/file_entry.dart';

/// Sort choices offered by My files. Directories remain grouped before files.
enum FileSortOrder {
  nameAscending,
  nameDescending,
  sizeDescending,
  sizeAscending,
  modifiedNewest,
  modifiedOldest,
}

/// Filter applied to the current folder without changing the underlying listing.
enum FileEntryFilter { all, folders, files }

List<FileEntry> filterFileEntries(
  Iterable<FileEntry> entries,
  FileEntryFilter filter,
) {
  return switch (filter) {
    FileEntryFilter.all => entries.toList(growable: false),
    FileEntryFilter.folders =>
      entries.where((entry) => entry.isFolder).toList(growable: false),
    FileEntryFilter.files =>
      entries.where((entry) => !entry.isFolder).toList(growable: false),
  };
}

/// Sorts files and folders independently, preserving the file-manager convention
/// that folders appear before files for every selected sort order.
List<FileEntry> sortFileEntries(
  Iterable<FileEntry> entries,
  FileSortOrder order,
) {
  final folders = entries.where((entry) => entry.isFolder).toList();
  final files = entries.where((entry) => !entry.isFolder).toList();

  int compare(FileEntry a, FileEntry b) {
    final primary = switch (order) {
      FileSortOrder.nameAscending =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      FileSortOrder.nameDescending =>
        b.name.toLowerCase().compareTo(a.name.toLowerCase()),
      FileSortOrder.sizeDescending => (b.size ?? 0).compareTo(a.size ?? 0),
      FileSortOrder.sizeAscending => (a.size ?? 0).compareTo(b.size ?? 0),
      FileSortOrder.modifiedNewest =>
        (b.modified?.millisecondsSinceEpoch ?? 0).compareTo(
          a.modified?.millisecondsSinceEpoch ?? 0,
        ),
      FileSortOrder.modifiedOldest =>
        (a.modified?.millisecondsSinceEpoch ?? 0).compareTo(
          b.modified?.millisecondsSinceEpoch ?? 0,
        ),
    };
    if (primary != 0) return primary;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  folders.sort(compare);
  files.sort(compare);
  return [...folders, ...files];
}
