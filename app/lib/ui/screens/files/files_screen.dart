import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_dimensions.dart';
import '../../../../core/design/app_typography.dart';
import '../../../../core/models/file_entry.dart';
import '../../../../core/utils/file_kind.dart';
import '../../../../core/utils/format.dart';
import '../../../services/api.dart';
import '../../../services/download_service.dart';
import '../../../services/image_pipeline.dart';
import '../../../services/thumbnail_cache.dart';
import '../../widgets/folder_picker.dart';
import '../../widgets/one_ui_action_bar.dart';
import '../../widgets/one_ui_empty_state.dart';
import '../../widgets/one_ui_file_tile.dart';
import '../../widgets/one_ui_sheet.dart';
import '../../widgets/upload_progress_dialog.dart';
import '../scanner/scanner_screen.dart';
import '../search/search_screen.dart';
import '../../navigation/file_opener.dart';
import 'file_details_sheet.dart';
import 'file_share_sheet.dart';

enum _Sort { name, size, newOld, oldNew }

/// A one-shot action another screen wants My files to perform, so a shortcut
/// like Home's "New folder" really creates a folder instead of only switching
/// tabs.
enum FilesIntent { upload, newFolder }

class FilesScreen extends StatefulWidget {
  final Api api;

  /// Folder to open at. Empty means the browser root.
  final String initialPath;

  /// Set by the shell when another screen asked My files to do something.
  final FilesIntent? intent;

  /// Called once [intent] has been started, so the shell can clear it and the
  /// same action can be requested again later.
  final VoidCallback? onIntentHandled;

  const FilesScreen({
    super.key,
    required this.api,
    this.initialPath = '',
    this.intent,
    this.onIntentHandled,
  });

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  late final DownloadService _downloads = DownloadService(widget.api);
  late final ImageRepository _images = ImageRepository(widget.api);
  late String _path = widget.initialPath;
  List<FileEntry> _items = [];
  bool _loading = true;
  bool _grid = false;
  bool _selecting = false;
  final Set<String> _selected = <String>{};
  String? _error;
  _Sort _sort = _Sort.name;

  /// Sorted view of [_items], invalidated whenever the listing or sort order
  /// changes. Sorting in `build` re-ran on every thumbnail that arrived, which
  /// made scrolling a large folder O(n log n) per preview.
  List<FileEntry>? _sortedCache;

  /// Paths with a download in flight. A set (not a single flag) so starting
  /// one download never silently swallows another one's request.
  final Set<String> _busyDownloads = <String>{};

  /// Paths the server cannot thumbnail (e.g. HEIC). Those rows keep the
  /// category icon instead of pulling full-resolution bytes into the list.
  final Set<String> _noThumbnail = <String>{};
  final Set<String> _loadingThumbs = <String>{};

  @override
  void initState() {
    super.initState();
    _attachDiskCache();
    load();
    // The first time this tab is opened the widget is created rather than
    // updated, so an initial intent has to be handled here too.
    final intent = widget.intent;
    if (intent != null) _scheduleIntent(intent);
  }

  @override
  void didUpdateWidget(covariant FilesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final intent = widget.intent;
    if (intent != null && intent != oldWidget.intent) _scheduleIntent(intent);
  }

  void _scheduleIntent(FilesIntent intent) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (intent) {
        case FilesIntent.upload:
          _pickAndUpload();
        case FilesIntent.newFolder:
          _createFolder();
      }
      widget.onIntentHandled?.call();
    });
  }

  /// Previews survive a restart; the cache is keyed by account + path so it
  /// never crosses accounts.
  Future<void> _attachDiskCache() async {
    try {
      final cache = await ThumbnailCache.open();
      if (mounted) _images.diskCache = cache;
    } catch (_) {}
  }

  Future<void> load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.api.listFiles(_path);
      if (!mounted) return;
      setState(() {
        _items = items.map(FileEntry.fromJson).toList();
        _sortedCache = null;
        _loading = false;
      });
      _prefetchThumbnails();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error =
            e is ApiException ? e.message : 'The folder could not be listed.';
        _loading = false;
      });
    }
  }

  /// Loads previews for image rows in the background, capped so opening a
  /// folder with thousands of photos never queues thousands of requests.
  void _prefetchThumbnails() {
    final images = _items
        .where((e) => e.category == Category.image)
        .take(60)
        .toList(growable: false);
    for (final entry in images) {
      unawaited(_ensureThumb(entry));
    }
  }

  ImageKey _thumbKey(FileEntry entry) => ImageRepository.keyFor(
        entry.toJson(),
        namespace: widget.api.session.cacheNamespace,
        rendition: ImageRendition.thumbnail,
      );

  Future<void> _ensureThumb(FileEntry entry) async {
    if (_noThumbnail.contains(entry.path) ||
        _loadingThumbs.contains(entry.path)) {
      return;
    }
    final key = _thumbKey(entry);
    if (_images.peekThumbnail(key) != null) return;
    _loadingThumbs.add(entry.path);
    try {
      await _images.thumbnail(key);
      if (mounted) setState(() {});
    } on ThumbnailUnavailable {
      if (mounted) setState(() => _noThumbnail.add(entry.path));
    } catch (_) {
      // Transient failures keep the icon; the next visit retries.
    } finally {
      _loadingThumbs.remove(entry.path);
    }
  }

  Uint8List? _thumbFor(FileEntry entry) {
    if (_noThumbnail.contains(entry.path)) return null;
    return _images.peekThumbnail(_thumbKey(entry));
  }

  // ------------------------------------------------------------- actions
  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Folder name'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final fullPath = _path.isEmpty ? name : '$_path/$name';
    try {
      await widget.api.createFolder(fullPath);
      await load();
    } catch (e) {
      if (mounted) _toast(e.toString());
    }
  }

  Future<void> _pickAndUpload() async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;
    if (!mounted) return;
    await UploadProgressDialog.show(
      context,
      api: widget.api,
      files: files,
      folder: _path,
    );
    if (mounted) await load();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // -------------------------------------------------------------- selection
  void _enterSelection(String path) {
    setState(() {
      _selecting = true;
      _selected.add(path);
    });
  }

  void _toggleSelect(String path) {
    setState(() {
      if (_selected.contains(path)) {
        _selected.remove(path);
      } else {
        _selected.add(path);
      }
    });
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  // ------------------------------------------------------------ navigation
  void _openEntry(FileEntry entry) {
    if (_selecting) {
      _toggleSelect(entry.path);
      return;
    }
    if (entry.isFolder) {
      setState(() => _path = entry.path);
      load();
      return;
    }
    _openFile(entry);
  }

  /// Every file type opens through the one shared [FileOpener], so behaviour
  /// is identical wherever a file is tapped from.
  void _openFile(FileEntry entry) {
    FileOpener.open(
      context,
      api: widget.api,
      entry: entry,
      siblings: _items,
    );
  }

  // ------------------------------------------------------------- file ops
  Future<void> _renameItem(FileEntry entry) async {
    final controller = TextEditingController(text: entry.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'New name'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty) return;
    try {
      await widget.api.rename(entry.path, newName);
      await load();
    } catch (e) {
      if (mounted) _toast(e.toString());
    }
  }

  Future<void> _moveItems({List<String>? paths}) async {
    final sourcePaths = paths ?? _selected.toList();
    if (sourcePaths.isEmpty) return;
    if (!mounted) return;
    final destination = await FolderPicker.pick(
      context,
      api: widget.api,
      title: 'Move to',
    );
    if (destination == null) return;
    try {
      await widget.api.batch(
        action: 'move',
        paths: sourcePaths,
        destination: destination,
      );
      _exitSelection();
      await load();
    } catch (e) {
      if (mounted) _toast(e.toString());
    }
  }

  Future<void> _copyItems({List<String>? paths}) async {
    final sourcePaths = paths ?? _selected.toList();
    if (sourcePaths.isEmpty) return;
    if (!mounted) return;
    final destination = await FolderPicker.pick(
      context,
      api: widget.api,
      title: 'Copy to',
    );
    if (destination == null) return;
    try {
      await widget.api.batch(
        action: 'copy',
        paths: sourcePaths,
        destination: destination,
      );
      _exitSelection();
      await load();
    } catch (e) {
      if (mounted) _toast(e.toString());
    }
  }

  Future<void> _deleteItems({List<String>? paths}) async {
    final sourcePaths = paths ?? _selected.toList();
    if (sourcePaths.isEmpty) return;
    final names = sourcePaths.map((p) => p.split('/').last).join(', ');
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move to Trash'),
        content: Text(sourcePaths.length == 1
            ? 'Move $names to trash?'
            : 'Move ${sourcePaths.length} items to trash?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Trash'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await widget.api.batch(action: 'delete', paths: sourcePaths);
      _exitSelection();
      await load();
    } catch (e) {
      if (mounted) _toast(e.toString());
    }
  }

  Future<void> _pickSort() async {
    final selected = await showDialog<_Sort>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Sort by'),
        children: [
          for (final option in _Sort.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, option),
              child: Row(
                children: [
                  Icon(
                    option == _sort
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: AppDimens.iconSmall,
                    color: option == _sort
                        ? AppColors.accentFor(Theme.of(context).brightness)
                        : AppColors.textTertiaryFor(
                            Theme.of(context).brightness),
                  ),
                  const SizedBox(width: AppDimens.space12),
                  Text(
                    _sortLabel(option),
                    style: AppTextStyle.rowTitle.copyWith(
                      fontWeight:
                          option == _sort ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    if (selected != null && selected != _sort) {
      setState(() {
        _sort = selected;
        _sortedCache = null;
      });
    }
  }

  static String _sortLabel(_Sort sort) => switch (sort) {
        _Sort.name => 'Name (A–Z)',
        _Sort.size => 'Size (largest first)',
        _Sort.newOld => 'Newest first',
        _Sort.oldNew => 'Oldest first',
      };

  Future<void> _downloadItem(FileEntry entry) async {
    // Already saving this exact file? Ignore the repeat instead of starting a
    // second transfer that would fight over the same destination.
    if (_busyDownloads.contains(entry.path)) return;
    setState(() => _busyDownloads.add(entry.path));
    try {
      final result = await _downloads.saveAs(
        remotePath: entry.path,
        fileName: entry.name,
        mimeType: FileKind.mimeFor(name: entry.name, type: 'file'),
      );
      if (!mounted) return;
      if (result == null) {
        _toast('Download cancelled');
      } else {
        _toast('Saved to ${result.location}');
      }
    } on SaveCancelled {
      if (mounted) _toast('Download cancelled');
    } catch (e) {
      if (mounted) _toast(e.toString());
    } finally {
      if (mounted) setState(() => _busyDownloads.remove(entry.path));
    }
  }

  // ---------------------------------------------------------- sorting
  List<FileEntry> get _sorted => _sortedCache ??= _computeSorted();

  List<FileEntry> _computeSorted() {
    final folders = _items.where((e) => e.isFolder).toList();
    final files = _items.where((e) => !e.isFolder).toList();
    int Function(FileEntry, FileEntry) cmp;
    switch (_sort) {
      case _Sort.name:
        cmp = (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
        break;
      case _Sort.size:
        cmp = (a, b) => (b.size ?? 0).compareTo(a.size ?? 0);
        break;
      case _Sort.newOld:
        cmp = (a, b) => (b.modified?.millisecondsSinceEpoch ?? 0)
            .compareTo(a.modified?.millisecondsSinceEpoch ?? 0);
        break;
      case _Sort.oldNew:
        cmp = (a, b) => (a.modified?.millisecondsSinceEpoch ?? 0)
            .compareTo(b.modified?.millisecondsSinceEpoch ?? 0);
        break;
    }
    folders.sort(cmp);
    files.sort(cmp);
    return [...folders, ...files];
  }

  // ------------------------------------------------------------------ bag
  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final accent = AppColors.accentFor(brightness);

    final crumb = _path.isEmpty ? 'My files' : _path.split('/').last;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ViewArea(
          title: crumb,
          subtitle: _path.isEmpty ? 'Browse your private cloud' : _path,
          selecting: _selecting,
          selectedCount: _selected.length,
          accent: accent,
          onBackToRoot: _path.isEmpty
              ? null
              : () {
                  setState(() => _path = '');
                  load();
                },
          onExitSelection: _exitSelection,
          onToggleView: () => setState(() => _grid = !_grid),
          isGrid: _grid,
          onNewFolder: _selecting ? null : _createFolder,
          onUpload: _selecting ? null : _pickAndUpload,
          onSearch: _selecting
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => SearchScreen(api: widget.api)),
                  ),
          onSort: _selecting ? null : _pickSort,
          onScan: _selecting
              ? null
              : () => Navigator.of(context)
                      .push(
                    MaterialPageRoute(
                      builder: (_) => ScannerScreen(
                        api: widget.api,
                        folder: _path,
                      ),
                    ),
                  )
                      .then((saved) {
                    if (saved == true) load();
                  }),
        ),

        // Breadcrumb strip
        if (!_selecting && _path.isNotEmpty)
          _Breadcrumb(
            path: _path,
            accent: accent,
            onBreadcrumb: (p) {
              setState(() => _path = p);
              load();
            },
          ),

        Expanded(
          child: _buildBody(),
        ),

        // Selection contextual action bar (lower interaction area)
        if (_selecting)
          OneUiActionBar(
            leading: IconButton(
              tooltip: 'Cancel selection',
              onPressed: _exitSelection,
              icon: const Icon(Icons.close_rounded),
            ),
            title: Format.count(_selected.length, 'item'),
            actions: [
              OneUiActionItem(
                icon: Icons.delete_outline_rounded,
                label: 'Trash',
                color: AppColors.errorFor(Theme.of(context).brightness),
                onTap: () => _deleteItems(),
              ),
              OneUiActionItem(
                icon: Icons.drive_file_move_outlined,
                label: 'Move',
                onTap: () => _moveItems(),
              ),
              OneUiActionItem(
                icon: Icons.copy_rounded,
                label: 'Copy',
                onTap: () => _copyItems(),
              ),
              OneUiActionItem(
                icon: Icons.share_outlined,
                label: 'Share',
                onTap: () => _shareSelected(),
              ),
              OneUiActionItem(
                icon: Icons.download_outlined,
                label: 'Save',
                onTap: () => _downloadSelected(),
              ),
            ],
          ),
      ],
    );
  }

  /// Multi-select download. One file uses the normal single-file save dialog;
  /// several files are streamed into one chosen folder with real progress, so
  /// "Save 5 items" can never quietly save just the first one.
  Future<void> _downloadSelected() async {
    final entries = _items.where((e) => _selected.contains(e.path)).toList();
    if (entries.isEmpty) return;
    if (entries.length == 1) {
      _exitSelection();
      await _downloadItem(entries.first);
      return;
    }

    final destination = await _downloads.pickBatchDestination();
    if (destination == null) return;
    if (!mounted) return;

    final cancel = CancelToken();
    final outcome = await showDialog<BatchSaveResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BatchDownloadDialog(
        items: [
          for (final e in entries) (remotePath: e.path, fileName: e.name),
        ],
        directory: destination,
        downloads: _downloads,
        cancel: cancel,
      ),
    );
    if (!mounted || outcome == null) return;
    _exitSelection();
    if (outcome.cancelled) {
      _toast('Download stopped after ${outcome.saved} file(s).');
    } else if (outcome.failures.isEmpty) {
      _toast('Saved ${outcome.saved} file(s) to ${outcome.directory}');
    } else {
      _toast(
        'Saved ${outcome.saved} of ${outcome.saved + outcome.failures.length}. '
        '${outcome.failures.length} failed.',
      );
    }
  }

  Future<void> _shareSelected() async {
    final entries = _items.where((e) => _selected.contains(e.path)).toList();
    if (entries.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FileShareSheet(api: widget.api, files: entries),
    );
    if (mounted) _exitSelection();
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return OneUiEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Can\'t reach NexaDrive',
        hint: _error,
        actionLabel: 'Retry',
        onAction: load,
      );
    }
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.16),
            OneUiEmptyState(
              icon: _path.isEmpty
                  ? Icons.cloud_upload_outlined
                  : Icons.folder_open_rounded,
              title: _path.isEmpty
                  ? 'Your cloud is empty'
                  : 'This folder is empty',
              hint: _path.isEmpty
                  ? 'Upload files or create a folder to get started.'
                  : 'Upload something here, or move files in from another folder.',
              actionLabel: 'Upload files',
              onAction: _pickAndUpload,
            ),
          ],
        ),
      );
    }

    final sorted = _sorted;
    final folders = sorted.where((e) => e.isFolder).toList();
    final files = sorted.where((e) => !e.isFolder).toList();

    return RefreshIndicator(
      onRefresh: load,
      child: _grid
          ? GridView.builder(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.pageMargin,
                AppDimens.space12,
                AppDimens.pageMargin,
                AppDimens.space24,
              ),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 170,
                mainAxisSpacing: AppDimens.space12,
                crossAxisSpacing: AppDimens.space12,
                childAspectRatio: 0.95,
              ),
              itemCount: sorted.length,
              itemBuilder: (context, i) {
                final e = sorted[i];
                return OneUiFileGridTile(
                  entry: e,
                  thumbnail: _thumbFor(e),
                  selected: _selected.contains(e.path),
                  selecting: _selecting,
                  onTap: (v) => _openEntry(v),
                  onLongPress: () => _enterSelection(e.path),
                );
              },
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.pageMargin,
                AppDimens.space4,
                AppDimens.pageMargin,
                AppDimens.space24,
              ),
              itemCount: (folders.isEmpty ? 0 : folders.length + 1) +
                  (files.isEmpty ? 0 : files.length + 1),
              itemBuilder: (context, i) {
                final Widget row;
                if (folders.isNotEmpty) {
                  if (i == 0) {
                    row = const _GroupHeader('Folders');
                  } else if (i <= folders.length) {
                    final e = folders[i - 1];
                    row = _fileRow(e);
                  } else if (files.isNotEmpty) {
                    final j = i - (folders.length + 1);
                    if (j == 0) {
                      row = const _GroupHeader('Files');
                    } else {
                      row = _fileRow(files[j - 1]);
                    }
                  } else {
                    row = const SizedBox.shrink();
                  }
                } else if (files.isNotEmpty) {
                  if (i == 0) {
                    row = const _GroupHeader('Files');
                  } else {
                    row = _fileRow(files[i - 1]);
                  }
                } else {
                  row = const SizedBox.shrink();
                }
                return row;
              },
            ),
    );
  }

  Widget _fileRow(FileEntry e) {
    return OneUiFileTile(
      entry: e,
      thumbnail: _thumbFor(e),
      selected: _selected.contains(e.path),
      selecting: _selecting,
      onTap: (v) => _openEntry(v),
      onLongPress: () => _enterSelection(e.path),
      trailing: _selecting
          ? null
          : IconButton(
              tooltip: 'More options',
              icon: Icon(
                Icons.more_vert_rounded,
                color: AppColors.textSecondaryFor(Theme.of(context).brightness),
              ),
              onPressed: () => _showFileMenu(context, e),
            ),
    );
  }

  // ---- batch download dialog is declared at file scope, below the state ----

  void _showFileMenu(BuildContext context, FileEntry entry) {
    showOneUiSheet<void>(
      context,
      builder: (sheetContext) => OneUiSheetBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OneUiSheetHeader(
              title: entry.name,
              subtitle:
                  '${FileKind.label(entry.category)} · ${Format.bytes(entry.size)}',
            ),
            OneUiSheetAction(
              icon: Icons.info_outline_rounded,
              title: 'Details',
              onTap: () {
                Navigator.pop(sheetContext);
                showOneUiSheet<void>(
                  context,
                  isScrollControlled: true,
                  builder: (_) =>
                      FileDetailsSheet(file: entry, api: widget.api),
                );
              },
            ),
            OneUiSheetAction(
              icon: Icons.share_outlined,
              title: 'Share',
              onTap: () {
                Navigator.pop(sheetContext);
                showOneUiSheet<void>(
                  context,
                  isScrollControlled: true,
                  builder: (_) =>
                      FileShareSheet(api: widget.api, files: [entry]),
                );
              },
            ),
            if (!entry.isFolder)
              OneUiSheetAction(
                icon: Icons.download_outlined,
                title: 'Download',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _downloadItem(entry);
                },
              ),
            if (entry.isFolder)
              OneUiSheetAction(
                icon: Icons.drive_file_move_outlined,
                title: 'Move',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _moveItems(paths: [entry.path]);
                },
              ),
            OneUiSheetAction(
              icon: Icons.edit_outlined,
              title: 'Rename',
              onTap: () {
                Navigator.pop(sheetContext);
                _renameItem(entry);
              },
            ),
            OneUiSheetAction(
              icon: Icons.delete_outline_rounded,
              title: 'Move to Trash',
              destructive: true,
              onTap: () {
                Navigator.pop(sheetContext);
                _deleteItems(paths: [entry.path]);
              },
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------------
class _ViewArea extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selecting;
  final int selectedCount;
  final Color accent;
  final VoidCallback? onBackToRoot;
  final VoidCallback onExitSelection;
  final VoidCallback onToggleView;
  final bool isGrid;
  final VoidCallback? onNewFolder;
  final VoidCallback? onUpload;
  final VoidCallback? onSearch;
  final VoidCallback? onScan;
  final VoidCallback? onSort;

  const _ViewArea({
    required this.title,
    required this.subtitle,
    required this.selecting,
    required this.selectedCount,
    required this.accent,
    this.onBackToRoot,
    required this.onExitSelection,
    required this.onToggleView,
    required this.isGrid,
    this.onNewFolder,
    this.onUpload,
    this.onSearch,
    this.onScan,
    this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageMargin,
        AppDimens.space20,
        AppDimens.pageMargin,
        AppDimens.space8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selecting ? Format.count(selectedCount, 'item') : title,
                  style: AppTextStyle.pageTitle.copyWith(
                    color: selecting
                        ? accent
                        : AppColors.textPrimaryFor(brightness),
                  ),
                ),
                if (!selecting) ...[
                  const SizedBox(height: AppDimens.space4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.caption.copyWith(
                        color: AppColors.textSecondaryFor(brightness)),
                  ),
                ],
                if (selecting && onBackToRoot != null) ...[
                  const SizedBox(height: AppDimens.space6),
                  TextButton.icon(
                    onPressed: onBackToRoot,
                    icon: const Icon(Icons.home_outlined,
                        size: AppDimens.iconSmall),
                    label: const Text('Back to My files'),
                  ),
                ],
              ],
            ),
          ),
          if (selecting)
            IconButton(
              tooltip: 'Cancel selection',
              onPressed: onExitSelection,
              icon: const Icon(Icons.close_rounded),
            )
          else ...[
            // Three controls, not seven: the primary action stays on screen
            // and the rest live in one overflow menu, so the page title still
            // has room on a phone.
            IconButton.filled(
              tooltip: 'Upload files',
              onPressed: onUpload,
              icon: const Icon(Icons.upload_rounded),
            ),
            IconButton(
              tooltip: 'Search files',
              onPressed: onSearch,
              icon: const Icon(Icons.search_rounded),
            ),
            PopupMenuButton<String>(
              tooltip: 'More actions',
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (value) {
                switch (value) {
                  case 'folder':
                    onNewFolder?.call();
                  case 'scan':
                    onScan?.call();
                  case 'sort':
                    onSort?.call();
                  case 'view':
                    onToggleView();
                  case 'up':
                    onBackToRoot?.call();
                }
              },
              itemBuilder: (context) => [
                if (onNewFolder != null)
                  const PopupMenuItem(
                    value: 'folder',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.create_new_folder_outlined),
                      title: Text('New folder'),
                    ),
                  ),
                if (onScan != null)
                  const PopupMenuItem(
                    value: 'scan',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.document_scanner_outlined),
                      title: Text('Scan document'),
                    ),
                  ),
                if (onSort != null)
                  const PopupMenuItem(
                    value: 'sort',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.sort_rounded),
                      title: Text('Sort by'),
                    ),
                  ),
                PopupMenuItem(
                  value: 'view',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      isGrid
                          ? Icons.view_list_outlined
                          : Icons.grid_view_outlined,
                    ),
                    title: Text(isGrid ? 'List view' : 'Grid view'),
                  ),
                ),
                if (onBackToRoot != null)
                  const PopupMenuItem(
                    value: 'up',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.arrow_upward_rounded),
                      title: Text('Back to My files'),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  final String path;
  final Color accent;
  final ValueChanged<String> onBreadcrumb;

  const _Breadcrumb({
    required this.path,
    required this.accent,
    required this.onBreadcrumb,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final parts = path.split('/');
    return SizedBox(
      // Meets the 48dp touch-target floor so crumbs are actually tappable.
      height: AppDimens.touchTarget,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppDimens.space16),
        children: [
          _crumb(context, brightness, 'My files', '', true),
          for (var i = 0; i < parts.length; i++) ...[
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: AppColors.textTertiaryFor(brightness),
            ),
            _crumb(
              context,
              brightness,
              parts[i],
              parts.sublist(0, i + 1).join('/'),
              i == parts.length - 1,
            ),
          ],
        ],
      ),
    );
  }

  Widget _crumb(
    BuildContext context,
    Brightness brightness,
    String label,
    String value,
    bool last,
  ) {
    return Semantics(
      button: !last,
      label: last ? '$label, current folder' : 'Go to $label',
      child: InkWell(
        onTap: last ? null : () => onBreadcrumb(value),
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        child: Container(
          alignment: Alignment.center,
          constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppDimens.space8),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.caption.copyWith(
              color: last ? AppColors.textPrimaryFor(brightness) : accent,
              fontWeight: last ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// Section label separating the grouped list (Folders / Files).
class _GroupHeader extends StatelessWidget {
  final String title;
  const _GroupHeader(this.title);

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.space4,
        AppDimens.space12,
        AppDimens.space4,
        AppDimens.space4,
      ),
      child: Text(
        title,
        style: AppTextStyle.sectionHeader.copyWith(
          color: AppColors.textSecondaryFor(brightness),
          fontSize: AppTextStyle.sectionHeader.fontSize! * 0.82,
        ),
      ),
    );
  }
}

/// Modal progress for a multi-file download. Shows the file being saved, the
/// completed count, and resolves with the batch outcome.
class _BatchDownloadDialog extends StatefulWidget {
  final List<BatchItem> items;
  final String directory;
  final DownloadService downloads;
  final CancelToken cancel;

  const _BatchDownloadDialog({
    required this.items,
    required this.directory,
    required this.downloads,
    required this.cancel,
  });

  @override
  State<_BatchDownloadDialog> createState() => _BatchDownloadDialogState();
}

class _BatchDownloadDialogState extends State<_BatchDownloadDialog> {
  int _completed = 0;
  String _current = '';

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final result = await widget.downloads.saveAllToDirectory(
      items: widget.items,
      directory: widget.directory,
      cancel: widget.cancel,
      onProgress: (completed, total, name) {
        if (!mounted) return;
        setState(() {
          _completed = completed;
          _current = name;
        });
      },
    );
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Saving files'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.items.length} files to ${widget.directory}',
              style: AppTextStyle.caption.copyWith(
                color: AppColors.textSecondaryFor(brightness),
              ),
            ),
            const SizedBox(height: AppDimens.space16),
            LinearProgressIndicator(
              value: widget.items.isEmpty
                  ? null
                  : _completed / widget.items.length,
            ),
            const SizedBox(height: AppDimens.space12),
            Text(
              _current,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.rowSubtitle.copyWith(
                color: AppColors.textPrimaryFor(brightness),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              widget.cancel.cancel();
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
