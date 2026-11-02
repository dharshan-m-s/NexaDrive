import 'package:flutter_test/flutter_test.dart';
import 'package:nexadrive/core/models/file_entry.dart';
import 'package:nexadrive/core/utils/file_sort.dart';

void main() {
  final entries = <FileEntry>[
    const FileEntry(
      name: 'zeta.txt',
      path: 'zeta.txt',
      type: 'file',
      size: 20,
      modifiedAt: '2026-01-01T00:00:00Z',
    ),
    const FileEntry(
      name: 'Alpha',
      path: 'Alpha',
      type: 'folder',
      size: 0,
      modifiedAt: '2026-02-01T00:00:00Z',
    ),
    const FileEntry(
      name: 'Beta',
      path: 'Beta',
      type: 'folder',
      size: 0,
      modifiedAt: '2026-03-01T00:00:00Z',
    ),
    const FileEntry(
      name: 'alpha.txt',
      path: 'alpha.txt',
      type: 'file',
      size: 5,
      modifiedAt: '2026-04-01T00:00:00Z',
    ),
  ];

  test('sorts folders before files for every order', () {
    for (final order in FileSortOrder.values) {
      final sorted = sortFileEntries(entries, order);
      expect(sorted.take(2).every((entry) => entry.isFolder), isTrue);
      expect(sorted.skip(2).every((entry) => !entry.isFolder), isTrue);
    }
  });

  test('supports ascending and descending name order', () {
    expect(
      sortFileEntries(entries, FileSortOrder.nameAscending)
          .map((entry) => entry.name)
          .toList(),
      ['Alpha', 'Beta', 'alpha.txt', 'zeta.txt'],
    );
    expect(
      sortFileEntries(entries, FileSortOrder.nameDescending)
          .map((entry) => entry.name)
          .toList(),
      ['Beta', 'Alpha', 'zeta.txt', 'alpha.txt'],
    );
  });

  test('supports both size directions', () {
    expect(
      sortFileEntries(entries, FileSortOrder.sizeDescending)
          .map((entry) => entry.name)
          .toList(),
      ['Alpha', 'Beta', 'zeta.txt', 'alpha.txt'],
    );
    expect(
      sortFileEntries(entries, FileSortOrder.sizeAscending)
          .map((entry) => entry.name)
          .toList(),
      ['Alpha', 'Beta', 'alpha.txt', 'zeta.txt'],
    );
  });

  test('supports newest and oldest modified dates', () {
    final newest = sortFileEntries(entries, FileSortOrder.modifiedNewest);
    final oldest = sortFileEntries(entries, FileSortOrder.modifiedOldest);
    expect(newest.first.name, 'Beta');
    expect(newest.last.name, 'zeta.txt');
    expect(oldest.first.name, 'Alpha');
    expect(oldest.last.name, 'alpha.txt');
  });

  test('filters folders and files without mutating the source list', () {
    expect(
      filterFileEntries(entries, FileEntryFilter.folders)
          .map((entry) => entry.name),
      ['Alpha', 'Beta'],
    );
    expect(
      filterFileEntries(entries, FileEntryFilter.files)
          .map((entry) => entry.name),
      ['zeta.txt', 'alpha.txt'],
    );
    expect(entries, hasLength(4));
  });
}
