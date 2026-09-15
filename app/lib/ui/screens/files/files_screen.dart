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
import '../../widgets/folder_picker.dart';
import '../../widgets/one_ui_action_bar.dart';
import '../../widgets/one_ui_empty_state.dart';
import '../../widgets/one_ui_file_tile.dart';
import '../../widgets/one_ui_sheet.dart';
import '../../widgets/upload_progress_dialog.dart';
import '../photos/photo_viewer.dart';
import '../media/video_player_screen.dart';
import '../media/audio_player_screen.dart';
import '../scanner/scanner_screen.dart';
import '../search/search_screen.dart';
import '../viewers/text_viewer_screen.dart';
import '../viewers/pdf_viewer_screen.dart';
import 'file_details_sheet.dart';
import 'file_share_sheet.dart';

enum _Sort { name, size, newOld, oldNew }

class FilesScreen extends StatefulWidget {
  final Api api;
  const FilesScreen({super.key, required this.api});

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  String _path = '';
  List<FileEntry> _items = [];
  bool _loading = true;
  bool _grid = false;
  bool _selecting = false;
  final Set<String> _selected = <String>{};
  String? _error;
  final _Sort _sort = _Sort.name;

  @override
  void initState() {
    super.initState();
    load();
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
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
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

  void _openFile(FileEntry entry) {
    switch (entry.category) {
      case Category.image:
        final images = _items.where((e) => e.category == Category.image).toList();
        final index = images.indexWhere((e) => e.path == entry.path);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PhotoViewer(
              photos: images.map((e) => e.toJson()).toList(),
              initialIndex: index < 0 ? 0 : index,
              api: widget.api,
            ),
          ),
        );
      case Category.video:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VideoPlayerScreen(file: entry, api: widget.api),
          ),
        );
      case Category.audio:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AudioPlayerScreen(file: entry, api: widget.api),
          ),
        );
      case Category.pdf:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PdfViewerScreen(file: entry, api: widget.api),
          ),
        );
      case Category.text:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TextViewerScreen(file: entry, api: widget.api),
          ),
        );
      default:
        _showUnsupported(entry);
    }
  }

  void _showUnsupported(FileEntry entry) {
    showOneUiSheet<void>(
      context,
      builder: (sheetContext) => OneUiSheetBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OneUiSheetHeader(title: entry.name, subtitle: 'Not viewable in NexaDrive'),
            Text(
              '${entry.category == Category.document ? 'Documents' : 'This format'}, '
              'can\'t be opened inside NexaDrive. Download it and open it with another app.',
              style: AppTextStyle.rowSubtitle.copyWith(
                color: AppColors.textSecondaryFor(Theme.of(context).brightness),
              ),
            ),
            const SizedBox(height: AppDimens.space24),
            FilledButton.icon(
              icon: const Icon(Icons.download_outlined, size: AppDimens.iconSmall),
              label: const Text('Download'),
              onPressed: () {
                Navigator.pop(sheetContext);
                _downloadItem(entry);
              },
            ),
          ],
        ),
      ),
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
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

  Future<void> _downloadItem(FileEntry entry) async {
    try {
      final outPath = await _pickSaveLocation(entry.name);
      if (outPath == null) return;
      if (!mounted) return;
      _toast('Download started…');
      await widget.api.downloadToFile(entry.path, outPath);
      if (mounted) _toast('Downloaded');
    } catch (e) {
      if (mounted) _toast(e.toString());
    }
  }

  /// Asks the user where to save [fileName] and returns a writable file path.
  ///
  /// file_picker 13's [FilePicker.saveFile] takes the file *contents* and
  /// returns a Uri; for downloads we only need the destination, so the dialog
  /// is driven with a placeholder byte and the returned location is used as
  /// the target path. Returns null when the user cancels.
  Future<String?> _pickSaveLocation(String fileName) async {
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      bytes: Uint8List(0),
      dialogTitle: 'Save $fileName',
    );
    if (uri == null) return null;
    return uri.toFilePath();
  }

  // ---------------------------------------------------------- sorting
  List<FileEntry> get _sorted {
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
                    MaterialPageRoute(builder: (_) => SearchScreen(api: widget.api)),
                  ),
          onScan: _selecting
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ScannerScreen(
                        api: widget.api,
                        folder: _path,
                      ),
                    ),
                  ).then((saved) {
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

  Future<void> _downloadSelected() async {
    for (final path in _selected.toList()) {
      final entry = _items.firstWhere((e) => e.path == path, orElse: () => FileEntry(name: path.split('/').last, path: path, type: 'file'));
      await _downloadItem(entry);
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
          children: const [SizedBox(height: 40)],
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
                AppDimens.pageMargin, AppDimens.space12, AppDimens.pageMargin, AppDimens.space24,
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
                  selected: _selected.contains(e.path),
                  selecting: _selecting,
                  onTap: (v) => _openEntry(v),
                  onLongPress: () => _enterSelection(e.path),
                );
              },
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.pageMargin, AppDimens.space4, AppDimens.pageMargin, AppDimens.space24,
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
              subtitle: '${FileKind.label(entry.category)} · ${Format.bytes(entry.size)}',
            ),
            OneUiSheetAction(
              icon: Icons.info_outline_rounded,
              title: 'Details',
              onTap: () {
                Navigator.pop(sheetContext);
                showOneUiSheet<void>(
                  context,
                  isScrollControlled: true,
                  builder: (_) => FileDetailsSheet(file: entry, api: widget.api),
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
                  builder: (_) => FileShareSheet(api: widget.api, files: [entry]),
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
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageMargin, AppDimens.space20, AppDimens.pageMargin, AppDimens.space8,
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
                    style: AppTextStyle.caption
                        .copyWith(color: AppColors.textSecondaryFor(brightness)),
                  ),
                ],
                if (selecting && onBackToRoot != null) ...[
                  const SizedBox(height: AppDimens.space6),
                  TextButton.icon(
                    onPressed: onBackToRoot,
                    icon: const Icon(Icons.home_outlined, size: AppDimens.iconSmall),
                    label: const Text('Back to My files'),
                  ),
                ],
              ],
            ),
          ),
          if (onBackToRoot != null && !selecting)
            IconButton(
              tooltip: 'Up to My files',
              onPressed: onBackToRoot,
              icon: const Icon(Icons.arrow_upward_rounded),
            ),
          if (selecting)
            IconButton(
              tooltip: 'Cancel selection',
              onPressed: onExitSelection,
              icon: const Icon(Icons.close_rounded),
            )
          else ...[
            IconButton(
              tooltip: 'Search files',
              onPressed: onSearch,
              icon: const Icon(Icons.search_rounded),
            ),
            IconButton(
              tooltip: isGrid ? 'List view' : 'Grid view',
              onPressed: onToggleView,
              icon: Icon(isGrid ? Icons.view_list_outlined : Icons.grid_view_outlined),
            ),
            IconButton(
              tooltip: 'New folder',
              onPressed: onNewFolder,
              icon: const Icon(Icons.create_new_folder_outlined),
            ),
            IconButton(
              tooltip: 'Scan document',
              onPressed: onScan,
              icon: const Icon(Icons.document_scanner_outlined),
            ),
            IconButton(
              tooltip: 'Upload files',
              onPressed: onUpload,
              icon: const Icon(Icons.upload_outlined),
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
    final parts = path.split('/');
    return Container(
      height: 40,
      color: Colors.transparent,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppDimens.pageMargin),
        children: [
          _crumb(context, 'My files', '', true),
          for (var i = 0; i < parts.length; i++) ...[
            const Icon(Icons.chevron_right_rounded, size: 16),
            _crumb(context, parts[i], parts.sublist(0, i + 1).join('/'), i == parts.length - 1),
          ],
        ],
      ),
    );
  }

  Widget _crumb(BuildContext context, String label, String value, bool last) {
    return GestureDetector(
      onTap: last ? null : () => onBreadcrumb(value),
      child: Center(
        child: Container(
          margin: EdgeInsets.zero,
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.caption.copyWith(
              color: last
                  ? AppColors.textPrimaryFor(Theme.of(context).brightness)
                  : accent,
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
        AppDimens.space4, AppDimens.space12, AppDimens.space4, AppDimens.space4,
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

Future<void> showFilesMenuFor(
  BuildContext context, {
  required Api api,
  required List<Map<String, dynamic>> files,
}) async {
  final entries = files.map(FileEntry.fromJson).toList();
  if (entries.isEmpty) return;
  // Used by shared-browse / multi-select flows to reuse the selection bar logic.
  final first = entries.first;
  if (entries.length == 1 && first.category == Category.image) {
    final images = files.where((e) {
      final f = FileEntry.fromJson(e);
      return f.category == Category.image;
    }).toList();
    final index = images.indexWhere((e) => (e['path']) == first.path);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoViewer(
          photos: images,
          initialIndex: index < 0 ? 0 : index,
          api: api,
        ),
      ),
    );
  }
}