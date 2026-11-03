import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_dimensions.dart';
import '../../../../core/design/app_motion.dart';
import '../../../../core/design/app_typography.dart';
import '../../../../core/models/file_entry.dart';
import '../../../../core/utils/file_sort.dart';
import '../../../../core/utils/file_kind.dart';
import '../../../../core/utils/format.dart';
import '../../../services/api.dart';
import '../../../services/download_service.dart';
import '../../../services/folder_source.dart'
    show FolderUploadPicker, SingleFileUploadPicker;
import '../../../services/image_pipeline.dart';
import '../../../services/thumbnail_cache.dart';
import '../../../services/upload_manager.dart';
import '../../widgets/folder_picker.dart';
import '../../widgets/nexa_action_bar.dart';
import '../../widgets/nexa_chip.dart';
import '../../widgets/nexa_file_tile.dart';
import '../../widgets/nexa_loading_state.dart';
import '../../widgets/nexa_sheet.dart';
import '../../widgets/upload_progress_dialog.dart';
import '../scanner/scanner_screen.dart';
import '../search/search_screen.dart';
import '../../navigation/file_opener.dart';
import 'file_share_sheet.dart';
import 'file_properties_sheet.dart';

enum _FileFilter { all, folders, files }

enum _UploadChoice { gallery, files }

/// A one-shot action another screen wants My files to perform.
enum FilesIntent { upload, uploadFolder, newFolder }

class FilesScreen extends StatefulWidget {
  final Api api;

  /// Folder to open at. Empty means the browser root.
  final String initialPath;

  /// Set by the shell when another screen asked My files to do something.
  final FilesIntent? intent;

  /// Called once [intent] has been started.
  final VoidCallback? onIntentHandled;
  final VoidCallback? onBackAtRoot;

  const FilesScreen({
    super.key,
    required this.api,
    this.initialPath = '',
    this.intent,
    this.onIntentHandled,
    this.onBackAtRoot,
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
  FileSortOrder _sort = FileSortOrder.nameAscending;
  _FileFilter _filter = _FileFilter.all;
  List<FileEntry>? _sortedCache;
  final Set<String> _busyDownloads = <String>{};
  final Set<String> _noThumbnail = <String>{};
  final Set<String> _loadingThumbs = <String>{};

  @override
  void initState() {
    super.initState();
    _attachDiskCache();
    load();
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
        case FilesIntent.uploadFolder:
          _pickAndUploadFolder();
        case FilesIntent.newFolder:
          _createFolder();
      }
      widget.onIntentHandled?.call();
    });
  }

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
    } finally {
      _loadingThumbs.remove(entry.path);
    }
  }

  Uint8List? _thumbFor(FileEntry entry) {
    if (_noThumbnail.contains(entry.path)) return null;
    return _images.peekThumbnail(_thumbKey(entry));
  }

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
    final choice = await showNexaSheet<_UploadChoice>(
      context,
      isScrollControlled: false,
      builder: (sheetContext) => NexaSheetBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NexaSheetHeader(
              title: 'Add to your cloud',
              subtitle: _path.isEmpty
                  ? 'Choose where to pick your files'
                  : 'Destination · $_path',
            ),
            NexaSheetAction(
              icon: Icons.photo_library_rounded,
              title: 'Choose from gallery',
              subtitle: 'Select multiple photos from your device library',
              iconColor: AppColors.accentFor(Theme.of(sheetContext).brightness),
              onTap: () => Navigator.pop(sheetContext, _UploadChoice.gallery),
            ),
            NexaSheetAction(
              icon: Icons.folder_open_rounded,
              title: 'Browse files',
              subtitle: 'Choose documents, videos, audio and other files',
              onTap: () => Navigator.pop(sheetContext, _UploadChoice.files),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;

    switch (choice) {
      case _UploadChoice.gallery:
        await _pickAndUploadGallery();
      case _UploadChoice.files:
        await _pickAndUploadFiles();
    }
  }

  Future<void> _pickAndUploadFiles() async {
    if (Platform.isAndroid) {
      // Keep the SAF URI path: selected documents stream directly from
      // ContentResolver in bounded chunks instead of being copied to cache.
      final picked = await const SingleFileUploadPicker().pick();
      if (picked == null || picked.isEmpty || !mounted) return;
      final sources = picked
          .map((file) => UploadSource(
                path: file.location,
                sourceUri: file.sourceUri,
                name: file.name,
                size: file.size,
              ))
          .toList(growable: false);
      await UploadProgressDialog.showSources(
        context,
        sources: sources,
        folder: _path,
        api: widget.api,
      );
    } else {
      final picked = await FilePicker.pickFiles();
      if (picked.isEmpty || !mounted) return;
      await UploadProgressDialog.show(
        context,
        files: picked,
        folder: _path,
      );
    }
    if (mounted) await load();
  }

  Future<void> _pickAndUploadGallery() async {
    if (Platform.isAndroid) {
      final picked = await const SingleFileUploadPicker().pickImages();
      if (picked == null || picked.isEmpty || !mounted) return;
      final sources = picked
          .map((file) => UploadSource(
                path: file.location,
                sourceUri: file.sourceUri,
                name: file.name,
                size: file.size,
              ))
          .toList(growable: false);
      await UploadProgressDialog.showSources(
        context,
        sources: sources,
        folder: _path,
        api: widget.api,
      );
    } else {
      final picked = await FilePicker.pickFiles(type: FileType.image);
      if (picked.isEmpty || !mounted) return;
      await UploadProgressDialog.show(
        context,
        files: picked,
        folder: _path,
      );
    }
    if (mounted) await load();
  }

  /// Uploads a whole folder, keeping its nested structure.
  Future<void> _pickAndUploadFolder() async {
    if (!mounted) return;
    final selection = await const FolderUploadPicker().pick();
    if (selection == null) return;
    if (!mounted) return;
    final sources = <UploadSource>[];
    for (final file in selection.files) {
      sources.add(UploadSource(
        path: file.location,
        sourceUri: file.sourceUri,
        name: file.name,
        size: file.size,
        relativePath: file.relativePath,
        temporary: selection.root != null,
      ));
    }
    if (sources.isEmpty) return;
    // Keep the selected folder as a visible destination, even when empty.
    try {
      await widget.api.createFolder(selection.destination(_path));
    } catch (e) {
      if (e is ApiException && e.status == 409) {
        // An existing folder is a valid merge target for this folder upload.
      } else {
        if (mounted) _toast(e.toString());
        return;
      }
    }
    if (!mounted) return;
    await UploadProgressDialog.showSources(
      context,
      sources: sources,
      folder: selection.destination(_path),
    );
    if (mounted) await load();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

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

  void _toggleSelectAll() {
    final visible = _visibleItems;
    setState(() {
      final allVisibleSelected = visible.isNotEmpty &&
          visible.every((entry) => _selected.contains(entry.path));
      if (allVisibleSelected) {
        _selected.removeAll(visible.map((entry) => entry.path));
      } else {        _selected.addAll(visible.map((entry) => entry.path));      }
      _selecting = _selected.isNotEmpty;
    });
  }

  bool _handleBack() {
    if (_selecting) {
      _exitSelection();
      return true;
    }
    if (_path.isNotEmpty) {
      final slash = _path.lastIndexOf('/');
      setState(() => _path = slash < 0 ? '' : _path.substring(0, slash));
      load();
      return true;
    }
    widget.onBackAtRoot?.call();
    return true;
  }

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

  void _openFile(FileEntry entry) {
    FileOpener.open(
      context,
      api: widget.api,
      entry: entry,
      siblings: _items,
    );
  }

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
    final selected = await showDialog<FileSortOrder>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Sort by'),
        children: [
          for (final option in FileSortOrder.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, option),
              child: Row(
                children: [
                  Icon(
                    option == _sort
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: AppDimens.iconSm,
                    color: option == _sort
                        ? AppColors.accentFor(Theme.of(context).brightness)
                        : AppColors.textTertiaryFor(
                            Theme.of(context).brightness),
                  ),
                  const SizedBox(width: AppDimens.spaceSm),
                  Text(
                    _sortLabel(option),
                    style: NexaTypography.rowTitle.copyWith(
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

  static String _sortLabel(FileSortOrder sort) => switch (sort) {
        FileSortOrder.nameAscending => 'Name (A–Z)',
        FileSortOrder.nameDescending => 'Name (Z–A)',
        FileSortOrder.sizeDescending => 'Size (largest first)',
        FileSortOrder.sizeAscending => 'Size (smallest first)',
        FileSortOrder.modifiedNewest => 'Newest first',
        FileSortOrder.modifiedOldest => 'Oldest first',
      };

  Future<void> _downloadItem(FileEntry entry) async {
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

  List<FileEntry> get _sorted => _sortedCache ??= _computeSorted();

  /// The current folder listing after the user's type filter is applied.
  List<FileEntry> get _visibleItems => filterFileEntries(
        _sorted,
        switch (_filter) {
          _FileFilter.all => FileEntryFilter.all,
          _FileFilter.folders => FileEntryFilter.folders,
          _FileFilter.files => FileEntryFilter.files,
        },
      );

  int get _folderCount => _items.where((entry) => entry.isFolder).length;
  int get _fileCount => _items.where((entry) => !entry.isFolder).length;

  List<FileEntry> _computeSorted() => sortFileEntries(_items, _sort);

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final accent = AppColors.accentFor(brightness);
    final crumb = _path.isEmpty ? 'My files' : _path.split('/').last;
    final subtitle = _path.isEmpty
        ? 'Your private cloud'
        : Format.count(_items.length, 'item');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ViewArea(
            title: crumb,
            subtitle: subtitle,
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
            onUploadFolder: _selecting ? null : _pickAndUploadFolder,
            onSearch: _selecting
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SearchScreen(api: widget.api),
                      ),
                    ),
            onSort: _selecting ? null : _pickSort,
            onRefresh: load,
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
          NexaRevealBar(
            visible: !_selecting && _path.isNotEmpty,
            alignment: Alignment.topLeft,
            child: _Breadcrumb(
              path: _path,
              accent: accent,
              onBreadcrumb: (p) {
                setState(() => _path = p);
                load();
              },
            ),
          ),
          NexaRevealBar(
            visible:
                !_selecting && !_loading && _error == null && _items.isNotEmpty,
            alignment: Alignment.topLeft,
            child: _FileFilterBar(
              selected: _filter,
              folderCount: _folderCount,
              fileCount: _fileCount,
              isGrid: _grid,
              onChanged: (value) => setState(() => _filter = value),
              onSort: _pickSort,
              onToggleView: () => setState(() => _grid = !_grid),
            ),
          ),
          Expanded(child: _body()),
          NexaRevealBar(
            visible: _selecting,
            child: NexaActionBar(
              leading: IconButton(
                tooltip: 'Cancel selection',
                onPressed: _exitSelection,
                icon: const Icon(Icons.close_rounded),
              ),
              title: Format.count(_selected.length, 'item'),
              actions: [
                NexaActionItem(
                  icon: _visibleItems.isNotEmpty &&
                          _visibleItems
                              .every((entry) => _selected.contains(entry.path))
                      ? Icons.deselect_rounded
                      : Icons.select_all_rounded,
                  label: _visibleItems.isNotEmpty &&
                          _visibleItems
                              .every((entry) => _selected.contains(entry.path))
                      ? 'Clear'
                      : 'Select all',
                  onTap: _toggleSelectAll,
                ),
                NexaActionItem(
                  icon: Icons.delete_outline_rounded,
                  label: 'Trash',
                  color: AppColors.errorFor(Theme.of(context).brightness),
                  onTap: () => _deleteItems(),
                ),
                NexaActionItem(
                  icon: Icons.drive_file_move_outlined,
                  label: 'Move',
                  onTap: () => _moveItems(),
                ),
                NexaActionItem(
                  icon: Icons.copy_rounded,
                  label: 'Copy',
                  onTap: () => _copyItems(),
                ),
                NexaActionItem(
                  icon: Icons.share_outlined,
                  label: 'Share',
                  onTap: () => _shareSelected(),
                ),
                NexaActionItem(
                  icon: Icons.download_outlined,
                  label: 'Save',
                  onTap: () => _downloadSelected(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
    if (!mounted) return;    final cancel = CancelToken();
    final outcome = await showDialog<BatchSaveResult>(      context: context,
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
    await showNexaFormSheet<void>(
      context,
      builder: (_) => FileShareSheet(api: widget.api, files: entries),
    );
    if (mounted) _exitSelection();
  }

  /// The body, cross-faded between states so a resolved listing settles in
  /// place instead of replacing the screen outright.
  Widget _body() => NexaStateSwitcher(
        stateKey: ValueKey(_bodyState),
        child: _buildBody(),
      );

  /// A stable identity for whichever body state is showing.
  String get _bodyState => _loading
      ? 'loading'
      : _error != null
          ? 'error'
          : _items.isEmpty
              ? 'empty'
              : _visibleItems.isEmpty
                  ? 'filtered-empty:${_filter.name}'
                  : 'content:${_grid ? 'grid' : 'list'}:${_filter.name}';

  Widget _buildBody() {
    final bottomClearance = MediaQuery.paddingOf(context).bottom;
    final bottomPadding = bottomClearance + AppDimens.bottomNavHeight;

    if (_loading) {
      return NexaSkeletonList(
        itemCount: 5,
        height: AppDimens.listHeightHero,
        showLeading: true,
        showTrailing: true,
      );
    }

    if (_error != null) {
      return RefreshIndicator(
        onRefresh: load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            AppDimens.pageMargin,
            AppDimens.space16,
            AppDimens.pageMargin,
            bottomPadding,
          ),
          children: [
            _FilesStatePanel(
              icon: Icons.cloud_off_rounded,
              title: "Can't reach NexaDrive",
              message: _error!,
              primaryLabel: 'Retry',
              primaryIcon: Icons.refresh_rounded,
              onPrimary: load,
            ),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            AppDimens.pageMargin,
            AppDimens.space16,
            AppDimens.pageMargin,
            bottomPadding,
          ),
          children: [
            _FilesStatePanel(
              icon: _path.isEmpty
                  ? Icons.cloud_upload_outlined
                  : Icons.folder_open_rounded,
              title: _path.isEmpty
                  ? 'Your cloud is empty'
                  : 'This folder is empty',
              message: _path.isEmpty
                  ? 'Start by adding files or creating a folder. Your private cloud is ready when you are.'
                  : 'Upload files here, or create a folder to keep this space organised.',
              primaryLabel: 'Upload files',
              primaryIcon: Icons.upload_rounded,
              onPrimary: _pickAndUpload,
              secondaryLabel: 'New folder',
              secondaryIcon: Icons.create_new_folder_outlined,
              onSecondary: _createFolder,
            ),
          ],
        ),
      );
    }

    final sorted = _visibleItems;
    if (sorted.isEmpty) {
      final noun = _filter == _FileFilter.folders ? 'folders' : 'files';
      return Center(
        child: _FilesStatePanel(
          icon: Icons.filter_alt_off_rounded,
          title: 'No $noun in this view',
          message: 'Change the filter to see the rest of this folder.',
          primaryLabel: 'Show all items',
          primaryIcon: Icons.filter_list_rounded,
          onPrimary: () => setState(() => _filter = _FileFilter.all),
        ),
      );
    }

    final folders = sorted.where((e) => e.isFolder).toList();
    final files = sorted.where((e) => !e.isFolder).toList();

    return RefreshIndicator(
      onRefresh: load,
      child: _grid
          ? GridView.builder(
              padding: EdgeInsets.fromLTRB(
                AppDimens.pageMargin,
                AppDimens.space8,
                AppDimens.pageMargin,
                bottomPadding,
              ),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 176,
                mainAxisSpacing: AppDimens.space12,
                crossAxisSpacing: AppDimens.space12,
                childAspectRatio: 0.80,
              ),
              itemCount: sorted.length,
              itemBuilder: (context, index) {
                final entry = sorted[index];
                return NexaFileGridTile(
                  entry: entry,
                  thumbnail: _thumbFor(entry),
                  selected: _selected.contains(entry.path),
                  selecting: _selecting,
                  onTap: _openEntry,
                  onLongPress: () => _enterSelection(entry.path),
                );
              },
            )
          : ListView.builder(
              padding: EdgeInsets.fromLTRB(
                AppDimens.pageMargin,
                AppDimens.space4,
                AppDimens.pageMargin,
                bottomPadding,
              ),
              itemCount: (folders.isEmpty ? 0 : folders.length + 1) +
                  (files.isEmpty ? 0 : files.length + 1),
              itemBuilder: (context, index) {
                if (folders.isNotEmpty && index <= folders.length) {
                  return index == 0
                      ? _GroupHeader('Folders', count: folders.length)
                      : _fileRow(folders[index - 1]);
                }

                final fileIndex =
                    index - (folders.isEmpty ? 0 : folders.length + 1);
                if (files.isNotEmpty && fileIndex == 0) {
                  return _GroupHeader('Files', count: files.length);
                }
                final itemIndex = fileIndex - 1;
                return itemIndex >= 0 && itemIndex < files.length
                    ? _fileRow(files[itemIndex])
                    : const SizedBox.shrink();
              },
            ),
    );
  }

  Widget _fileRow(FileEntry entry) {
    final brightness = Theme.of(context).brightness;
    final radius = BorderRadius.circular(AppDimens.radiusMedium);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimens.space8),
      child: Material(
        color: AppColors.surfaceFor(brightness),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: AppColors.separatorFor(brightness).withValues(alpha: 0.72),
            width: 0.7,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: NexaFileTile(
          entry: entry,
          thumbnail: _thumbFor(entry),
          selected: _selected.contains(entry.path),
          selecting: _selecting,
          onTap: _openEntry,
          onLongPress: () => _enterSelection(entry.path),
          trailing: _selecting
              ? null
              : IconButton(
                  tooltip: 'More options',
                  icon: Icon(
                    Icons.more_horiz_rounded,
                    color: AppColors.textSecondaryFor(brightness),
                  ),
                  onPressed: () => _showFileMenu(context, entry),
                ),
        ),
      ),
    );
  }

  void _showFileMenu(BuildContext context, FileEntry entry) {
    showNexaSheet<void>(
      context,
      builder: (sheetContext) => NexaSheetBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NexaSheetHeader(
              title: entry.name,
              subtitle:
                  '${FileKind.label(entry.category)} · ${Format.bytes(entry.size)}',
            ),
            NexaSheetAction(
              icon: Icons.info_outline_rounded,
              title: 'Properties',
              onTap: () {
                Navigator.pop(sheetContext);
                showNexaFormSheet<void>(
                  context,
                  builder: (_) =>
                      FilePropertiesSheet(entry: entry, api: widget.api),
                );
              },
            ),
            NexaSheetAction(
              icon: Icons.share_outlined,
              title: 'Share',
              onTap: () {
                Navigator.pop(sheetContext);
                showNexaFormSheet<void>(
                  context,
                  builder: (_) =>
                      FileShareSheet(api: widget.api, files: [entry]),
                );
              },
            ),
            if (!entry.isFolder)
              NexaSheetAction(
                icon: Icons.download_outlined,
                title: 'Download',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _downloadItem(entry);
                },
              ),
            if (entry.isFolder)
              NexaSheetAction(
                icon: Icons.drive_file_move_outlined,
                title: 'Move',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _moveItems(paths: [entry.path]);
                },
              ),
            NexaSheetAction(
              icon: Icons.edit_outlined,
              title: 'Rename',
              onTap: () {
                Navigator.pop(sheetContext);
                _renameItem(entry);
              },
            ),
            NexaSheetAction(
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

enum _FileHeaderAction {
  refresh,
  newFolder,
  uploadFolder,
  scan,
  sort,
  toggleView,
}

/// The compact file-browser toolbar. Upload, search and overflow actions share
/// the title row so the page starts with one coherent control group instead
/// of an oversized upload row floating below a separate header.
/// My files toolbar. The title and overflow stay on their own row; Search
/// and Upload share a single compact action row below it.
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
  final VoidCallback? onUploadFolder;
  final VoidCallback? onSearch;
  final VoidCallback? onScan;
  final VoidCallback? onSort;
  final VoidCallback? onRefresh;

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
    this.onUploadFolder,
    this.onSearch,
    this.onScan,
    this.onSort,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageMargin,
        AppDimens.space12,
        AppDimens.pageMargin,
        AppDimens.space8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedSwitcher(
                      duration: AppMotion.resolve(context, AppMotion.fast),
                      child: Text(
                        selecting ? Format.count(selectedCount, 'item') : title,
                        key: ValueKey(
                          selecting ? 'selection:$selectedCount' : title,                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NexaTypography.pageTitle.copyWith(
                          fontSize: 22,
                          color: selecting
                              ? accent
                              : AppColors.labelPrimaryFor(brightness),
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.45,
                        ),
                      ),
                    ),
                    if (!selecting)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NexaTypography.caption.copyWith(
                          fontSize: 11.5,
                          color: AppColors.labelSecondaryFor(brightness),
                        ),
                      )
                    else if (onBackToRoot != null)
                      InkWell(
                        onTap: onBackToRoot,
                        borderRadius:
                            BorderRadius.circular(AppDimens.radiusSmall),
                        child: Padding(
                          padding: const EdgeInsets.only(
                              top: 2, right: 6, bottom: 2),
                          child: Text(
                            'Back to My files',
                            style: NexaTypography.caption.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (selecting)
                IconButton(
                  tooltip: 'Cancel selection',
                  onPressed: onExitSelection,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.fillFor(brightness),
                    minimumSize: const Size(
                      AppDimens.touchTarget,
                      AppDimens.touchTarget,
                    ),
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  icon: const Icon(Icons.close_rounded),
                )
              else
                PopupMenuButton<_FileHeaderAction>(
                  tooltip: 'More actions',
                  icon: const Icon(Icons.more_horiz_rounded, size: 22),
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.fillFor(brightness),
                    foregroundColor: AppColors.labelPrimaryFor(brightness),
                    minimumSize: const Size(
                      AppDimens.touchTarget,
                      AppDimens.touchTarget,
                    ),
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  onSelected: (action) {
                    switch (action) {
                      case _FileHeaderAction.refresh:
                        onRefresh?.call();
                        break;
                      case _FileHeaderAction.newFolder:
                        onNewFolder?.call();
                        break;
                      case _FileHeaderAction.uploadFolder:
                        onUploadFolder?.call();
                        break;
                      case _FileHeaderAction.scan:
                        onScan?.call();
                        break;
                      case _FileHeaderAction.sort:
                        onSort?.call();
                        break;
                      case _FileHeaderAction.toggleView:
                        onToggleView();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: _FileHeaderAction.refresh,
                      child: _FileMenuLabel(
                        icon: Icons.refresh_rounded,
                        label: 'Refresh folder',
                      ),
                    ),
                    const PopupMenuDivider(),
                    if (onNewFolder != null)
                      const PopupMenuItem(
                        value: _FileHeaderAction.newFolder,
                        child: _FileMenuLabel(
                          icon: Icons.create_new_folder_outlined,
                          label: 'New folder',
                        ),
                      ),
                    if (onUploadFolder != null)
                      const PopupMenuItem(
                        value: _FileHeaderAction.uploadFolder,
                        child: _FileMenuLabel(
                          icon: Icons.drive_folder_upload_outlined,
                          label: 'Upload folder',
                        ),
                      ),
                    if (onScan != null)
                      const PopupMenuItem(
                        value: _FileHeaderAction.scan,
                        child: _FileMenuLabel(
                          icon: Icons.document_scanner_outlined,
                          label: 'Scan document',
                        ),
                      ),
                    if (onSort != null)
                      const PopupMenuItem(
                        value: _FileHeaderAction.sort,
                        child: _FileMenuLabel(
                          icon: Icons.sort_rounded,
                          label: 'Sort by…',
                        ),
                      ),
                    PopupMenuItem(
                      value: _FileHeaderAction.toggleView,
                      child: _FileMenuLabel(
                        icon: isGrid
                            ? Icons.view_list_rounded
                            : Icons.grid_view_rounded,
                        label: isGrid ? 'List view' : 'Grid view',
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (!selecting) ...[
            const SizedBox(height: AppDimens.space10),
            Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message: 'Search files',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: onSearch,
                        borderRadius: BorderRadius.circular(13),
                        child: Ink(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 13),
                          decoration: BoxDecoration(
                            color: AppColors.fillFor(brightness),
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(
                              color: AppColors.dividerFor(brightness),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.search_rounded,
                                size: 20,
                                color: AppColors.labelSecondaryFor(brightness),
                              ),
                              const SizedBox(width: AppDimens.space8),
                              Expanded(
                                child: Text(
                                  'Search files',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyle.subheadline.copyWith(
                                    color:
                                        AppColors.labelSecondaryFor(brightness),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppDimens.space8),
                Tooltip(
                  message: 'Upload files',
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: FilledButton(
                      onPressed: onUpload,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(44, 44),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        backgroundColor:
                            AppColors.accentContainerFor(brightness),
                        foregroundColor: AppColors.accentTextFor(brightness),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      child: const Icon(Icons.upload_rounded, size: 19),
                    ),
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

class _FilesStatePanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final IconData? secondaryIcon;
  final VoidCallback? onSecondary;

  const _FilesStatePanel({
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimary,
    this.secondaryLabel,
    this.secondaryIcon,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final accent = AppColors.accentFor(brightness);
    final isConnectionIssue = primaryLabel == 'Retry';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          padding: const EdgeInsets.all(AppDimens.space16),
          decoration: BoxDecoration(
            color: AppColors.surfaceFor(brightness),
            borderRadius: BorderRadius.circular(AppDimens.radiusLarge),
            border: Border.all(
              color: AppColors.dividerFor(brightness).withValues(alpha: 0.9),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: isConnectionIssue
                          ? AppColors.errorContainerFor(brightness)
                          : AppColors.accentContainerFor(brightness),
                      borderRadius:
                          BorderRadius.circular(AppDimens.radiusMedium),
                    ),
                    child: Icon(
                      icon,
                      size: 26,
                      color: isConnectionIssue
                          ? AppColors.errorFor(brightness)
                          : accent,
                    ),
                  ),
                  const SizedBox(width: AppDimens.space12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isConnectionIssue) ...[
                          Text(
                            'CONNECTION ISSUE',
                            style: AppTextStyle.caption1.copyWith(
                              color: AppColors.errorFor(brightness),
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: AppDimens.space4),
                        ],
                        Text(
                          title,
                          style: AppTextStyle.title3.copyWith(
                            color: AppColors.labelPrimaryFor(brightness),
                          ),
                        ),
                        const SizedBox(height: AppDimens.space4),
                        Text(
                          message,
                          style: AppTextStyle.subheadline.copyWith(
                            color: AppColors.labelSecondaryFor(brightness),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDimens.space16),
              Wrap(
                alignment: WrapAlignment.start,
                spacing: AppDimens.space8,
                runSpacing: AppDimens.space8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: onPrimary,
                    style: FilledButton.styleFrom(
                      foregroundColor: AppColors.accentTextFor(brightness),
                      backgroundColor: AppColors.accentContainerFor(brightness),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimens.space16,
                        vertical: AppDimens.space8,
                      ),
                      minimumSize: const Size(0, AppDimens.touchTarget),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppDimens.radiusPill),
                      ),
                    ),
                    icon: Icon(primaryIcon, size: 18),
                    label: Text(primaryLabel),
                  ),
                  if (secondaryLabel != null && onSecondary != null)
                    OutlinedButton.icon(
                      onPressed: onSecondary,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.labelPrimaryFor(brightness),
                        side: BorderSide(
                          color: AppColors.separatorFor(brightness),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDimens.space16,
                          vertical: AppDimens.space8,
                        ),
                        minimumSize: const Size(0, AppDimens.touchTarget),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppDimens.radiusPill),                        ),
                      ),
                      icon: Icon(secondaryIcon, size: 18),
                      label: Text(secondaryLabel!),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileMenuLabel extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FileMenuLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [        Icon(icon, size: AppDimens.iconSm),
        const SizedBox(width: AppDimens.space10),
        Text(label),
      ],
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
      height: AppDimens.touchTarget,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppDimens.pageMargin),
        children: [
          _crumb(
            context,
            brightness,
            'My files',
            '',
            false,
            icon: Icons.home_outlined,
          ),
          for (var i = 0; i < parts.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 17,
                color: AppColors.labelTertiaryFor(brightness),
              ),
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
    bool last, {
    IconData? icon,
  }) {
    return Semantics(
      button: !last,
      label: last ? '$label, current folder' : 'Go to $label',
      child: Material(
        color: last
            ? AppColors.accentContainerFor(brightness).withValues(alpha: 0.68)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppDimens.radiusSmall),
        child: InkWell(
          onTap: last ? null : () => onBreadcrumb(value),
          borderRadius: BorderRadius.circular(AppDimens.radiusSmall),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppDimens.space8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: accent),
                    const SizedBox(width: AppDimens.space4),
                  ],
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NexaTypography.caption.copyWith(
                        color: last
                            ? AppColors.labelPrimaryFor(brightness)
                            : accent,
                        fontWeight: last ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String title;
  final int count;

  const _GroupHeader(this.title, {required this.count});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.space4,
        AppDimens.space16,
        AppDimens.space4,
        AppDimens.space8,
      ),
      child: Row(
        children: [
          Text(
            title,
            style: NexaTypography.sectionHeader.copyWith(
              color: AppColors.labelPrimaryFor(brightness),
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(width: AppDimens.space6),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.space6,
              vertical: AppDimens.space2,
            ),
            decoration: BoxDecoration(
              color: AppColors.fillFor(brightness),
              borderRadius: BorderRadius.circular(AppDimens.radiusPill),
            ),
            child: Text(
              '$count',
              style: NexaTypography.caption.copyWith(
                color: AppColors.labelSecondaryFor(brightness),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
              style: NexaTypography.caption.copyWith(
                color: AppColors.textSecondaryFor(brightness),
              ),
            ),
            const SizedBox(height: AppDimens.spaceMd),
            LinearProgressIndicator(
              value: widget.items.isEmpty
                  ? null
                  : _completed / widget.items.length,
            ),
            const SizedBox(height: AppDimens.spaceSm),
            Text(
              _current,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NexaTypography.rowSubtitle.copyWith(
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

/// Compact folder/file filters. Counts always reflect the complete folder,
/// not only the currently selected filter.
class _FileFilterBar extends StatelessWidget {
  final _FileFilter selected;
  final int folderCount;
  final int fileCount;
  final bool isGrid;
  final ValueChanged<_FileFilter> onChanged;
  final VoidCallback onSort;
  final VoidCallback onToggleView;

  const _FileFilterBar({
    required this.selected,
    required this.folderCount,
    required this.fileCount,
    required this.isGrid,
    required this.onChanged,
    required this.onSort,
    required this.onToggleView,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final buttonStyle = IconButton.styleFrom(
      backgroundColor: AppColors.fillFor(brightness),
      foregroundColor: AppColors.labelSecondaryFor(brightness),
      minimumSize: const Size(
        AppDimens.touchTarget,
        AppDimens.touchTarget,
      ),
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusSmall),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.pageMargin),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  NexaChip.tonal(
                    label: 'All ${folderCount + fileCount}',
                    selected: selected == _FileFilter.all,
                    onTap: () => onChanged(_FileFilter.all),
                  ),
                  const SizedBox(width: AppDimens.space6),
                  NexaChip.tonal(
                    label: 'Folders $folderCount',
                    leadingIcon: Icons.folder_outlined,
                    selected: selected == _FileFilter.folders,
                    onTap: () => onChanged(_FileFilter.folders),
                  ),
                  const SizedBox(width: AppDimens.space6),
                  NexaChip.tonal(
                    label: 'Files $fileCount',
                    leadingIcon: Icons.insert_drive_file_outlined,
                    selected: selected == _FileFilter.files,
                    onTap: () => onChanged(_FileFilter.files),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppDimens.space6),
          IconButton(
            tooltip: 'Sort files',
            onPressed: onSort,
            style: buttonStyle,
            icon: const Icon(Icons.sort_rounded, size: 20),
          ),
          const SizedBox(width: AppDimens.space4),
          IconButton(
            tooltip: isGrid ? 'Switch to list view' : 'Switch to grid view',
            onPressed: onToggleView,
            style: buttonStyle,
            icon: Icon(
              isGrid ? Icons.view_list_rounded : Icons.grid_view_rounded,
              size: 19,
            ),
          ),
        ],
      ),
    );
  }
}