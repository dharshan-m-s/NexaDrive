import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/design/app_dimensions.dart';
import '../../../../core/design/app_haptics.dart';
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
import '../../../services/trash_restore.dart';
import '../../../services/upload_manager.dart';
import '../../widgets/folder_picker.dart';
import '../../widgets/nexa_action_bar.dart';
import '../../widgets/nexa_file_glyph.dart';
import '../../widgets/nexa_file_tile.dart';
import '../../widgets/nexa_layout_picker.dart';
import '../../widgets/nexa_loading_state.dart';
import '../../widgets/nexa_sheet.dart';
import '../../widgets/nexa_surface.dart';
import '../../widgets/nexa_undo.dart';
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

  /// Lets the shell hide the floating navigation while a range is selected.
  final ValueChanged<bool>? onSelectionChanged;

  const FilesScreen({
    super.key,
    required this.api,
    this.initialPath = '',
    this.intent,
    this.onIntentHandled,
    this.onBackAtRoot,
    this.onSelectionChanged,
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
  int _gridColumns = 2;
  bool _selecting = false;
  final Set<String> _selected = <String>{};
  int? _activePointer;
  Offset? _lastPointerPosition;
  bool _dragSelecting = false;
  int? _dragAnchorIndex;
  Set<String> _dragBaseSelection = const <String>{};
  int _keyboardAnchorIndex = 0;
  int _keyboardExtentIndex = 0;
  bool _dropHovering = false;
  FileEntry? _hoveredEntry;
  double? _pinchBaseColumns;
  final Map<String, _FileCellRef> _fileCellKeys = <String, _FileCellRef>{};
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
    _loadGridColumns();
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
    // Images, videos and PDFs all have bounded server-rendered previews.
    // Audio, documents and folders keep their glyph treatment.
    final previewable = _items
        .where(
          (e) =>
              e.category == Category.image ||
              e.category == Category.video ||
              e.category == Category.pdf,
        )
        .take(60)
        .toList(growable: false);
    for (final entry in previewable) {
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
            child: const Text('Cancel'),
          ),
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
              iconColor: Theme.of(sheetContext).colorScheme.primary,
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
          .map(
            (file) => UploadSource(
              path: file.location,
              sourceUri: file.sourceUri,
              name: file.name,
              size: file.size,
            ),
          )
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
      await UploadProgressDialog.show(context, files: picked, folder: _path);
    }
    if (mounted) await load();
  }

  Future<void> _pickAndUploadGallery() async {
    if (Platform.isAndroid) {
      final picked = await const SingleFileUploadPicker().pickImages();
      if (picked == null || picked.isEmpty || !mounted) return;
      final sources = picked
          .map(
            (file) => UploadSource(
              path: file.location,
              sourceUri: file.sourceUri,
              name: file.name,
              size: file.size,
            ),
          )
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
      await UploadProgressDialog.show(context, files: picked, folder: _path);
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
      sources.add(
        UploadSource(
          path: file.location,
          sourceUri: file.sourceUri,
          name: file.name,
          size: file.size,
          relativePath: file.relativePath,
          temporary: selection.root != null,
        ),
      );
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

  /// Turns OS file drops into the same upload sources used by the picker, so
  /// dropped folders keep their relative structure.
  Future<void> _handleDroppedFiles(List<DropItem> dropped) async {
    final sources = <UploadSource>[];

    Future<void> add(DropItem item, String relative) async {
      if (item is DropItemDirectory) {
        final prefix = '$relative${item.name}/';
        for (final child in item.children) {
          await add(child, prefix);
        }
        return;
      }
      final size = await item.length();
      sources.add(
        UploadSource(
          path: item.path,
          name: item.name,
          size: size,
          relativePath: relative,
          temporary: item.fromPromise,
        ),
      );
    }

    for (final item in dropped) {
      await add(item, '');
    }
    if (sources.isEmpty || !mounted) return;
    await UploadProgressDialog.showSources(
      context,
      sources: sources,
      folder: _path,
    );
    if (mounted) await load();
  }

  static const _gridColumnsPreference = 'nexadrive.files.grid_columns';

  Future<void> _loadGridColumns() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_gridColumnsPreference);
      if (saved != null && mounted) {
        setState(() => _gridColumns = NexaGridLayout.clamp(saved));
      }
    } catch (_) {
      // The grid still works with the default density.
    }
  }

  Future<void> _saveGridColumns(int columns) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_gridColumnsPreference, columns);
    } catch (_) {
      // The selected density remains active for this session.
    }
  }

  Future<void> _showGridLayoutPicker() async {
    final selected = await showNexaGridLayoutPicker(
      context: context,
      columns: _gridColumns,
      title: 'Files layout',
      subtitle: 'Choose how many files fit across the grid.',
    );
    if (selected == null || !mounted || selected == _gridColumns) return;
    setState(() {
      _gridColumns = selected;
      _grid = true;
    });
    await _saveGridColumns(selected);
  }

  /// List and grid cells can briefly coexist during the view cross-fade, so
  /// their hit-test keys must live in separate namespaces. The ref keeps the
  /// real path alongside the key, which is what range selection needs.
  GlobalKey _keyForFileCell(String path, {required bool grid}) {
    final id = '${grid ? 'grid' : 'list'}:$path';
    return _fileCellKeys
        .putIfAbsent(
          id,
          () => _FileCellRef(path: path, key: GlobalKey()),
        )
        .key;
  }

  void _pruneFileCellKeys() {
    _fileCellKeys.removeWhere((_, ref) => ref.key.currentContext == null);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _onPointerDown(PointerDownEvent event) {
    _activePointer = event.pointer;
    _lastPointerPosition = event.position;
  }

  void _onPointerMove(PointerMoveEvent event) {
    _lastPointerPosition = event.position;
    if (!_dragSelecting || event.pointer != _activePointer) return;
    final path = _pathAtPosition(event.position);
    if (path == null) return;
    final visible = _visibleItems;
    final index = visible.indexWhere((entry) => entry.path == path);
    if (index >= 0) _selectRangeTo(index);
  }

  void _onPointerUp(PointerEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    _lastPointerPosition = null;
    _dragSelecting = false;
    _dragAnchorIndex = null;
    _dragBaseSelection = const <String>{};
  }

  void _onScaleStart(ScaleStartDetails details) {
    // Cheap early capture when the recognizer happens to accept with two
    // fingers. The common one-finger accept is handled lazily in _onScaleUpdate.
    if (details.pointerCount == 2) {
      // Density is a grid concept; make the pinch visible even when the user
      // is currently in the compact list.
      if (!_grid) setState(() => _grid = true);
      _pinchBaseColumns = _gridColumns.toDouble();
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount < 2 || _dragSelecting) return;
    var base = _pinchBaseColumns;
    if (base == null) {
      // Density is a grid concept; make the pinch visible even when the user
      // starts from the compact list. Switch before capturing the base so the
      // list -> grid transition is part of the same gesture.
      if (!_grid) setState(() => _grid = true);
      base = _gridColumns.toDouble();
      _pinchBaseColumns = base;
    }
    if (!base.isFinite || base <= 0) return;
    final scale = details.scale;
    // Interactive pinching is inverted relative to layout density: fingers
    // coming together (scale < 1) reveal more columns, spreading shows fewer.
    if (!scale.isFinite || scale <= 0) return;
    final columns = NexaGridLayout.clamp((base / scale).round());
    if (columns == _gridColumns) return;
    setState(() => _gridColumns = columns);
    AppHaptics.selection();
  }

  void _onScaleEnd(ScaleEndDetails details) {
    final base = _pinchBaseColumns;
    _pinchBaseColumns = null;
    if (base == null) return;
    unawaited(_saveGridColumns(_gridColumns));
  }

  String? _pathAtPosition(Offset globalPosition) {
    String? hitPath;
    final stale = <String>[];
    for (final entry in _fileCellKeys.entries) {
      final renderObject = entry.value.key.currentContext?.findRenderObject();
      if (renderObject is! RenderBox ||
          !renderObject.attached ||
          !renderObject.hasSize) {
        stale.add(entry.key);
        continue;
      }
      final rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
      if (rect.contains(globalPosition)) hitPath = entry.value.path;
    }
    for (final path in stale) {
      _fileCellKeys.remove(path);
    }
    return hitPath;
  }

  void _beginDragSelection(String path) {
    final visible = _visibleItems;
    final anchor = visible.indexWhere((entry) => entry.path == path);
    if (anchor < 0) return;
    if (!_selecting) {
      AppHaptics.impact();
      _dragBaseSelection = <String>{path};
      setState(() {
        _selecting = true;
        _selected
          ..clear()
          ..addAll(_dragBaseSelection);
      });
      widget.onSelectionChanged?.call(true);
    } else {
      _dragBaseSelection = Set<String>.from(_selected);
    }
    _dragAnchorIndex = anchor;
    _dragSelecting = true;
    final hit = _pathAtPosition(_lastPointerPosition ?? Offset.zero);
    final target =
        hit == null ? anchor : visible.indexWhere((entry) => entry.path == hit);
    _selectRangeTo(target < 0 ? anchor : target);
  }

  void _selectRangeTo(int index) {
    final anchor = _dragAnchorIndex;
    if (anchor == null) return;
    final visible = _visibleItems;
    if (index < 0 || index >= visible.length) return;
    final start = index < anchor ? index : anchor;
    final end = index < anchor ? anchor : index;
    final next = <String>{..._dragBaseSelection};
    for (var i = start; i <= end; i++) {
      next.add(visible[i].path);
    }
    if (next.length == _selected.length && next.every(_selected.contains)) {
      return;
    }
    setState(() {
      _selected
        ..clear()
        ..addAll(next);
    });
    AppHaptics.selection();
  }

  void _toggleSelect(String path) {
    AppHaptics.selection();
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
    widget.onSelectionChanged?.call(false);
  }

  void _toggleSelectAll() {
    AppHaptics.selection();
    final visible = _visibleItems;
    setState(() {
      final allVisibleSelected = visible.isNotEmpty &&
          visible.every((entry) => _selected.contains(entry.path));
      if (allVisibleSelected) {
        _selected.removeAll(visible.map((entry) => entry.path));
      } else {
        _selected.addAll(visible.map((entry) => entry.path));
      }
      _selecting = _selected.isNotEmpty;
    });
    widget.onSelectionChanged?.call(_selecting);
  }

  void _ensureSelecting() {
    if (_selecting) return;
    AppHaptics.impact();
    setState(() => _selecting = true);
    widget.onSelectionChanged?.call(true);
  }

  void _selectAllVisible() {
    final visible = _visibleItems;
    if (visible.isEmpty) return;
    _ensureSelecting();
    _dragBaseSelection = const <String>{};
    _dragAnchorIndex = 0;
    _keyboardAnchorIndex = 0;
    _keyboardExtentIndex = visible.length - 1;
    setState(() {
      _selected
        ..clear()
        ..addAll(visible.map((entry) => entry.path));
    });
    AppHaptics.selection();
  }

  void _selectAllFromHere() {
    final visible = _visibleItems;
    if (visible.isEmpty) return;
    final anchor = _dragAnchorIndex ?? _keyboardAnchorIndex;
    final start = anchor.clamp(0, visible.length - 1);
    _ensureSelecting();
    _dragBaseSelection = const <String>{};
    _dragAnchorIndex = start;
    _keyboardAnchorIndex = start;
    _keyboardExtentIndex = visible.length - 1;
    _selectRangeTo(visible.length - 1);
  }

  void _startRangeSelection(int anchor, {Set<String>? base}) {
    if (anchor < 0) return;
    _ensureSelecting();
    _dragAnchorIndex = anchor;
    _keyboardAnchorIndex = anchor;
    _keyboardExtentIndex = anchor;
    _dragBaseSelection =
        base == null ? const <String>{} : Set<String>.from(base);
  }

  /// A grid row is [_gridColumns] items wide; a list row is one item.
  int get _verticalStep => _grid ? _gridColumns : 1;

  void _moveKeyboardSelection(int delta, {required bool extend}) {
    if (_shortcutsBlocked()) return;
    final visible = _visibleItems;
    if (visible.isEmpty) return;
    if (!_selecting) _startRangeSelection(0);

    final extent = _keyboardExtentIndex.clamp(0, visible.length - 1);
    final next = (extent + delta).clamp(0, visible.length - 1);
    _keyboardExtentIndex = next;
    if (!extend) {
      _dragBaseSelection = const <String>{};
      _dragAnchorIndex = next;
      _keyboardAnchorIndex = next;
    }
    _selectRangeTo(next);
  }

  /// Ctrl/Cmd toggles a single item; Shift extends from the previous anchor.
  /// A plain tap keeps the existing long-press/tap behavior.
  void _handleEntryTap(FileEntry entry) {
    if (_shortcutsBlocked()) return;
    final toggle = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final extend = HardwareKeyboard.instance.isShiftPressed;
    if (!_selecting && !toggle && !extend) {
      _openEntry(entry);
      return;
    }
    final visible = _visibleItems;
    final index = visible.indexWhere((item) => item.path == entry.path);
    if (index < 0) return;

    if (extend) {
      final anchor = (_dragAnchorIndex ?? _keyboardAnchorIndex).clamp(
        0,
        visible.length - 1,
      );
      _ensureSelecting();
      _dragBaseSelection = Set<String>.from(_selected);
      _dragAnchorIndex = anchor;
      _keyboardAnchorIndex = anchor;
      _keyboardExtentIndex = index;
      _selectRangeTo(index);
      return;
    }
    _ensureSelecting();
    _dragAnchorIndex = index;
    _keyboardAnchorIndex = index;
    _keyboardExtentIndex = index;
    _toggleSelect(entry.path);
  }

  bool _shortcutsBlocked() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return false;
    final focused = focus.context?.widget;
    return focused is EditableText || focused is TextField;
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
    FileOpener.open(context, api: widget.api, entry: entry, siblings: _items);
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
            child: const Text('Cancel'),
          ),
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
      final moved = await widget.api.batch(
        action: 'move',
        paths: sourcePaths,
        destination: destination,
      );
      _exitSelection();
      await load();
      if (!mounted) return;
      final origin = _path;
      NexaUndo.show(
        context,
        'Moved ${sourcePaths.length == 1 ? '1 item' : '${sourcePaths.length} items'}',
        onAction: () async {
          try {
            await widget.api.batch(
              action: 'move',
              paths: moved,
              destination: origin,
            );
            if (mounted) await load();
          } catch (e) {
            if (mounted) _toast('Couldn’t undo the move. $e');
          }
        },
      );
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
        content: Text(
          sourcePaths.length == 1
              ? 'Move $names to trash?'
              : 'Move ${sourcePaths.length} items to trash?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Trash'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final trashed = await widget.api.batch(
        action: 'delete',
        paths: sourcePaths,
      );
      _exitSelection();
      await load();
      if (!mounted) return;
      NexaUndo.show(
        context,
        sourcePaths.length == 1
            ? 'Moved 1 item to Trash'
            : 'Moved ${sourcePaths.length} items to Trash',
        onAction: () async {
          try {
            await TrashRestore.paths(widget.api, trashed);
            if (mounted) await load();
          } catch (e) {
            if (mounted) _toast(e.toString());
          }
        },
      );
    } catch (e) {
      if (mounted) _toast(e.toString());
    }
  }

  /// One compact sheet for the two decisions that affect a listing: how it is
  /// ordered and which kinds of items are visible.
  Future<void> _pickSort() async {
    var sort = _sort;
    var filter = _filter;
    await showNexaSheet<void>(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final scheme = Theme.of(sheetContext).colorScheme;
          return NexaSheetBody(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                NexaSheetHeader(
                  title: 'Sort & filter',
                  subtitle: 'Choose how this folder reads.',
                  trailing: TextButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('Done'),
                  ),
                ),
                const SizedBox(height: AppDimens.space8),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.space16,
                  ),
                  child: Text(
                    'SHOW',
                    style: AppTextStyle.sectionHeader.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Wrap(
                  spacing: AppDimens.space8,
                  children: [
                    for (final (value, label) in [
                      (_FileFilter.all, 'All'),
                      (_FileFilter.folders, 'Folders'),
                      (_FileFilter.files, 'Files'),
                    ])
                      ChoiceChip(
                        label: Text(label),
                        selected: filter == value,
                        onSelected: (_) => setSheetState(() => filter = value),
                      ),
                  ],
                ),
                const SizedBox(height: AppDimens.space20),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.space16,
                  ),
                  child: Text(
                    'SORT BY',
                    style: AppTextStyle.sectionHeader.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                for (final option in FileSortOrder.values)
                  ListTile(
                    leading: Icon(
                      option == sort
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: option == sort
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                    title: Text(
                      _sortLabel(option),
                      style: AppTextStyle.bodyLarge.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                    onTap: () => setSheetState(() => sort = option),
                  ),
                const SizedBox(height: AppDimens.space8),
              ],
            ),
          );
        },
      ),
    );
    if (!mounted) return;
    setState(() {
      _sort = sort;
      _filter = filter;
      _sortedCache = null;
    });
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
      });

  int get _folderCount => _items.where((entry) => entry.isFolder).length;
  int get _fileCount => _items.where((entry) => !entry.isFolder).length;

  List<FileEntry> _computeSorted() => sortFileEntries(_items, _sort);

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
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
            gridColumns: _gridColumns,
            onLayout: _showGridLayoutPicker,
            onNewFolder: _selecting ? null : _createFolder,
            onUpload: _selecting ? null : _pickAndUpload,
            onUploadFolder: _selecting ? null : _pickAndUploadFolder,
            onSearch: _selecting
                ? null
                : (query) => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SearchScreen(
                          api: widget.api,
                          initialQuery: query,
                        ),
                      ),
                    ),
            onSort: _selecting ? null : _pickSort,
            onRefresh: load,
            onScan: _selecting
                ? null
                : () => Navigator.of(context)
                        .push(
                      MaterialPageRoute(
                        builder: (_) =>
                            ScannerScreen(api: widget.api, folder: _path),
                      ),
                    )
                        .then((saved) {
                      if (saved == true) load();
                    }),
          ),
          NexaRevealBar(
            // The path is always readable, even one level down, so navigation
            // never depends on remembering what the header title means.
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
              onChanged: (value) => setState(() => _filter = value),
            ),
          ),
          Expanded(
            child: Focus(
              autofocus: true,
              child: CallbackShortcuts(
                bindings: {
                  SingleActivator(
                    LogicalKeyboardKey.keyA,
                    control: true,
                  ): _selectAllVisible,
                  SingleActivator(
                    LogicalKeyboardKey.keyA,
                    meta: true,
                  ): _selectAllVisible,
                  SingleActivator(LogicalKeyboardKey.escape): () {
                    if (!_shortcutsBlocked() && _selecting) _exitSelection();
                  },
                  SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                      _moveKeyboardSelection(_verticalStep, extend: false),
                  SingleActivator(
                    LogicalKeyboardKey.arrowDown,
                    shift: true,
                  ): () => _moveKeyboardSelection(_verticalStep, extend: true),
                  SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                      _moveKeyboardSelection(-_verticalStep, extend: false),
                  SingleActivator(
                    LogicalKeyboardKey.arrowUp,
                    shift: true,
                  ): () => _moveKeyboardSelection(-_verticalStep, extend: true),
                  SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                      _moveKeyboardSelection(1, extend: false),
                  SingleActivator(
                    LogicalKeyboardKey.arrowRight,
                    shift: true,
                  ): () => _moveKeyboardSelection(1, extend: true),
                  SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                      _moveKeyboardSelection(-1, extend: false),
                  SingleActivator(
                    LogicalKeyboardKey.arrowLeft,
                    shift: true,
                  ): () => _moveKeyboardSelection(-1, extend: true),
                },
                child: DropTarget(
                  enable: !_selecting,
                  onDragEntered: (_) => setState(() => _dropHovering = true),
                  onDragExited: (_) => setState(() => _dropHovering = false),
                  onDragDone: (details) {
                    setState(() => _dropHovering = false);
                    unawaited(_handleDroppedFiles(details.files));
                  },
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: GestureDetector(
                          onScaleStart: _onScaleStart,
                          onScaleUpdate: _onScaleUpdate,
                          onScaleEnd: _onScaleEnd,
                          child: Listener(
                            onPointerDown: _onPointerDown,
                            onPointerMove: _onPointerMove,
                            onPointerUp: _onPointerUp,
                            onPointerCancel: _onPointerUp,
                            child: NotificationListener<ScrollNotification>(
                              onNotification: (_) {
                                _pruneFileCellKeys();
                                return false;
                              },
                              child: _body(),
                            ),
                          ),
                        ),
                      ),
                      if (_hoveredEntry != null &&
                          !_dropHovering &&
                          MediaQuery.sizeOf(context).width >= 900)
                        Positioned(
                          right: AppDimens.space16,
                          top: AppDimens.space16,
                          child: IgnorePointer(
                            child: _HoverPreview(
                              entry: _hoveredEntry!,
                              thumbnail: _thumbFor(_hoveredEntry!),
                            ),
                          ),
                        ),
                      if (_dropHovering)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Padding(
                              padding: const EdgeInsets.all(AppDimens.space16),
                              child: NexaSurface(
                                level: NexaSurfaceLevel.floating,
                                radius: AppDimens.radiusMedium,
                                child: Center(
                                  child: Semantics(
                                    label: 'Drop files to upload',
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.cloud_upload_outlined,
                                        ),
                                        const SizedBox(
                                          width: AppDimens.space12,
                                        ),
                                        Flexible(
                                          child: Text(
                                            'Drop to upload to ${_path.isEmpty ? 'My files' : _path}',
                                            style: AppTextStyle.titleSmall,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          NexaRevealBar(
            visible: _selecting,
            child: NexaActionBar(
              aboveFloatingNav: true,
              leading: IconButton(
                tooltip: 'Cancel selection',
                onPressed: _exitSelection,
                icon: const Icon(Icons.close_rounded),
              ),
              title: Format.count(_selected.length, 'item'),
              titleWidget: AnimatedSwitcher(
                duration: AppMotion.resolve(context, AppMotion.fast),
                switchInCurve: AppMotion.curveFor(context, AppMotion.standard),
                switchOutCurve: AppMotion.curveFor(context, AppMotion.standard),
                child: Text(
                  Format.count(_selected.length, 'item'),
                  key: ValueKey(_selected.length),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.titleMedium.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              actions: [
                NexaActionItem(
                  icon: _visibleItems.isNotEmpty &&
                          _visibleItems.every(
                            (entry) => _selected.contains(entry.path),
                          )
                      ? Icons.deselect_rounded
                      : Icons.select_all_rounded,
                  label: _visibleItems.isNotEmpty &&
                          _visibleItems.every(
                            (entry) => _selected.contains(entry.path),
                          )
                      ? 'Clear'
                      : 'Select all',
                  onTap: _toggleSelectAll,
                ),
                NexaActionItem(
                  icon: Icons.playlist_add_rounded,
                  label: 'From here',
                  onTap: _selectAllFromHere,
                ),
                NexaActionItem(
                  icon: Icons.delete_outline_rounded,
                  label: 'Trash',
                  color: Theme.of(context).colorScheme.error,
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
    await showNexaFormSheet<void>(
      context,
      builder: (_) => FileShareSheet(api: widget.api, files: entries),
    );
    if (mounted) _exitSelection();
  }

  /// The body, cross-faded between states so a resolved listing settles in
  /// place instead of replacing the screen outright.
  Widget _body() =>
      NexaStateSwitcher(stateKey: ValueKey(_bodyState), child: _buildBody());

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
    // The shell already publishes pill-inclusive clearance through MediaQuery.
    // Adding the pill height again left a dead strip between the last row and
    // the navigation. Standalone windows still get a calm minimum gutter.
    final bottomClearance = MediaQuery.paddingOf(context).bottom;
    final bottomPadding = bottomClearance > AppDimens.space24
        ? bottomClearance
        : AppDimens.space24;

    if (_loading) {
      return NexaSkeletonList(
        itemCount: 5,
        height: AppDimens.listHeightHero,
        showLeading: true,
        showTrailing: true,
        padding: EdgeInsets.only(bottom: bottomPadding),
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
              title: 'That folder didn’t load',
              message:
                  'Can’t reach NexaDrive. Check your connection and try again.',
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
    final sections = <(String, List<FileEntry>)>[
      if (folders.isNotEmpty) ('Folders', folders),
      if (files.isNotEmpty) ('Files', files),
    ];

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
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _gridColumns,
                mainAxisSpacing: AppDimens.space16,
                crossAxisSpacing: AppDimens.space12,
                childAspectRatio: 0.72,
              ),
              itemCount: sorted.length,
              itemBuilder: (context, index) {
                final entry = sorted[index];
                return NexaFileGridTile(
                  key: _keyForFileCell(entry.path, grid: true),
                  entry: entry,
                  thumbnail: _thumbFor(entry),
                  selected: _selected.contains(entry.path),
                  selecting: _selecting,
                  onTap: _handleEntryTap,
                  onLongPress: () => _beginDragSelection(entry.path),
                  onSecondaryTap: (item) => _showFileMenu(context, item),
                  onHoverEnter: (item) => setState(() => _hoveredEntry = item),
                  onHoverExit: () => setState(() => _hoveredEntry = null),
                );
              },
            )
          : CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(
                  child: SizedBox(height: AppDimens.space4),
                ),
                for (final section in sections) ...[
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _StickyHeaderDelegate(
                      child: Material(
                        color: Theme.of(context).colorScheme.surface,
                        child: _GroupHeader(
                          section.$1,
                          count: section.$2.length,
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _FlatFileGroup(
                      entries: section.$2,
                      selecting: _selecting,
                      thumbnailFor: _thumbFor,
                      isSelected: (path) => _selected.contains(path),
                      keyFor: (path) => _keyForFileCell(path, grid: false),
                      onOpen: _handleEntryTap,
                      onLongPress: (entry) => _beginDragSelection(entry.path),
                      onToggleSelect: _toggleSelect,
                      onMore: (entry) => _showFileMenu(context, entry),
                      onSecondaryTap: (entry) => _showFileMenu(context, entry),
                      onHoverEnter: (entry) =>
                          setState(() => _hoveredEntry = entry),
                      onHoverExit: () => setState(() => _hoveredEntry = null),
                    ),
                  ),
                ],
                SliverToBoxAdapter(
                  child: SizedBox(height: bottomPadding),
                ),
              ],
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
  uploadFiles,
  uploadFolder,
  scan,
  sort,
  toggleView,
  layout,
}

/// The compact file-browser toolbar. Upload, search and overflow actions share
/// the title row so the page starts with one coherent control group instead
/// of an oversized upload row floating below a separate header.
/// My files toolbar. The title and overflow stay on their own row; Search
/// and Upload share a single compact action row below it.
class _ViewArea extends StatefulWidget {
  final String title;
  final String subtitle;
  final bool selecting;
  final int selectedCount;
  final Color accent;
  final VoidCallback? onBackToRoot;
  final VoidCallback onExitSelection;
  final VoidCallback onToggleView;
  final bool isGrid;
  final int gridColumns;
  final VoidCallback onLayout;
  final VoidCallback? onNewFolder;
  final VoidCallback? onUpload;
  final VoidCallback? onUploadFolder;
  final ValueChanged<String>? onSearch;
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
    required this.gridColumns,
    required this.onLayout,
    this.onNewFolder,
    this.onUpload,
    this.onUploadFolder,
    this.onSearch,
    this.onScan,
    this.onSort,
    this.onRefresh,
  });

  @override
  State<_ViewArea> createState() => _ViewAreaState();
}

class _ViewAreaState extends State<_ViewArea> {
  bool _searchExpanded = false;
  final SearchController _searchController = SearchController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final widget = this.widget;
    final title = widget.title;
    final subtitle = widget.subtitle;
    final selecting = widget.selecting;
    final selectedCount = widget.selectedCount;
    final accent = widget.accent;
    final onBackToRoot = widget.onBackToRoot;
    final onExitSelection = widget.onExitSelection;
    final onToggleView = widget.onToggleView;
    final isGrid = widget.isGrid;
    final gridColumns = widget.gridColumns;
    final onLayout = widget.onLayout;
    final onNewFolder = widget.onNewFolder;
    final onUpload = widget.onUpload;
    final onUploadFolder = widget.onUploadFolder;
    final onSearch = widget.onSearch;
    final onScan = widget.onScan;
    final onSort = widget.onSort;
    final onRefresh = widget.onRefresh;

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
                          selecting ? 'selection:$selectedCount' : title,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.titleLarge.copyWith(
                          color: selecting ? accent : scheme.onSurface,
                        ),
                      ),
                    ),
                    if (!selecting)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.bodySmall.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      )
                    else if (onBackToRoot == null)
                      Text(
                        'Drag across items to select · Tap to refine',
                        style: AppTextStyle.bodySmall.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      )
                    else
                      InkWell(
                        onTap: onBackToRoot,
                        borderRadius: BorderRadius.circular(
                          AppDimens.radiusSmall,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppDimens.space6,
                            vertical: AppDimens.space2,
                          ),
                          child: Text(
                            'Back to My files',
                            style: AppTextStyle.labelLarge.copyWith(
                              color: accent,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (selecting)
                IconButton.filledTonal(
                  tooltip: 'Cancel selection',
                  onPressed: onExitSelection,
                  style: IconButton.styleFrom(
                    backgroundColor: scheme.surfaceContainerHigh,
                    foregroundColor: scheme.onSurface,
                  ),
                  icon: const Icon(Icons.close_rounded),
                )
              else ...[
                IconButton(
                  tooltip: 'Search files',
                  onPressed: () => setState(() {
                    _searchExpanded = !_searchExpanded;
                    if (!_searchExpanded) _searchController.clear();
                  }),
                  style: IconButton.styleFrom(
                    backgroundColor: scheme.surfaceContainerHigh,
                    foregroundColor: scheme.onSurface,
                    minimumSize: const Size(
                        AppDimens.touchTarget, AppDimens.touchTarget),
                    padding: EdgeInsets.zero,
                    shape: const StadiumBorder(),
                  ),
                  icon: Icon(_searchExpanded
                      ? Icons.close_rounded
                      : Icons.search_rounded),
                ),
                PopupMenuButton<_FileHeaderAction>(
                  tooltip: 'More actions',
                  icon: const Icon(
                    Icons.more_horiz_rounded,
                    size: AppDimens.iconMedium,
                  ),
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(
                    backgroundColor: scheme.surfaceContainerHigh,
                    foregroundColor: scheme.onSurface,
                    minimumSize: const Size(
                      AppDimens.touchTarget,
                      AppDimens.touchTarget,
                    ),
                    padding: EdgeInsets.zero,
                    shape: const StadiumBorder(),
                  ),
                  onSelected: (action) {
                    switch (action) {
                      case _FileHeaderAction.refresh:
                        onRefresh?.call();
                        break;
                      case _FileHeaderAction.newFolder:
                        onNewFolder?.call();
                        break;
                      case _FileHeaderAction.uploadFiles:
                        onUpload?.call();
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
                      case _FileHeaderAction.layout:
                        onLayout();
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
                    if (onUpload != null)
                      const PopupMenuItem(
                        value: _FileHeaderAction.uploadFiles,
                        child: _FileMenuLabel(
                          icon: Icons.upload_rounded,
                          label: 'Upload files',
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
                          label: 'Sort & filter…',
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
                    PopupMenuItem(
                      value: _FileHeaderAction.layout,
                      child: _FileMenuLabel(
                        icon: Icons.view_module_rounded,
                        label: 'Grid layout · $gridColumns',
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          if (!selecting && _searchExpanded) ...[
            const SizedBox(height: AppDimens.space8),
            SearchBar(
              controller: _searchController,
              autoFocus: true,
              hintText: 'Search files',
              leading: const Padding(
                padding: EdgeInsets.only(left: AppDimens.space4),
                child: Icon(Icons.search_rounded),
              ),
              trailing: [
                IconButton(
                  tooltip: 'Close search',
                  onPressed: () {
                    setState(() {
                      _searchExpanded = false;
                      _searchController.clear();
                    });
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
              onSubmitted: (query) {
                final value = query.trim();
                if (value.isNotEmpty) onSearch?.call(value);
              },
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
    final scheme = Theme.of(context).colorScheme;
    final isConnectionIssue = primaryLabel == 'Retry';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: NexaSurface(
          level: NexaSurfaceLevel.grouped,
          radius: AppDimens.radiusCard,
          padding: const EdgeInsets.all(AppDimens.space16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: AppDimens.touchTargetLarge + AppDimens.space2,
                    height: AppDimens.touchTargetLarge + AppDimens.space2,
                    decoration: BoxDecoration(
                      color: isConnectionIssue
                          ? scheme.errorContainer
                          : scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(
                        AppDimens.radiusMedium,
                      ),
                    ),
                    child: Icon(
                      icon,
                      size: AppDimens.iconLarge,
                      color: isConnectionIssue
                          ? scheme.onErrorContainer
                          : scheme.onSecondaryContainer,
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
                            style: AppTextStyle.labelMedium.copyWith(
                              color: scheme.error,
                            ),
                          ),
                          const SizedBox(height: AppDimens.space4),
                        ],
                        Text(
                          title,
                          style: AppTextStyle.titleLarge.copyWith(
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: AppDimens.space4),
                        Text(
                          message,
                          style: AppTextStyle.bodyMedium.copyWith(
                            color: scheme.onSurfaceVariant,
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
                    icon: Icon(primaryIcon, size: AppDimens.iconSmall),
                    label: Text(primaryLabel),
                  ),
                  if (secondaryLabel != null && onSecondary != null)
                    OutlinedButton.icon(
                      onPressed: onSecondary,
                      icon: Icon(
                        secondaryIcon,
                        size: AppDimens.iconSmall,
                      ),
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
      children: [
        Icon(icon, size: AppDimens.iconSm),
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
    final scheme = Theme.of(context).colorScheme;
    final parts = path.split('/');
    return SizedBox(
      height: AppDimens.touchTarget,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppDimens.pageMargin),
        children: [
          _crumb(scheme, 'My files', '', false, icon: Icons.home_outlined),
          for (var i = 0; i < parts.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppDimens.space2),
              child: Icon(
                Icons.chevron_right_rounded,
                size: AppDimens.iconSmall,
                color: scheme.onSurfaceVariant,
              ),
            ),
            _crumb(
              scheme,
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
    ColorScheme scheme,
    String label,
    String value,
    bool last, {
    IconData? icon,
  }) {
    return Semantics(
      button: !last,
      label: last ? '$label, current folder' : 'Go to $label',
      child: Material(
        color: last ? scheme.secondaryContainer : Colors.transparent,
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
                    Icon(icon, size: AppDimens.iconSmall, color: accent),
                    const SizedBox(width: AppDimens.space4),
                  ],
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.labelMedium.copyWith(
                        color: last ? scheme.onSecondaryContainer : accent,
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

/// A hit-test key plus the file path it belongs to. Keeping them together is
/// what lets a drag resolve a touched cell back into a contiguous path range.
class _FileCellRef {
  final String path;
  final GlobalKey key;

  const _FileCellRef({required this.path, required this.key});
}

/// A flat, grouped list of file rows. One tonal surface per section replaces
/// the old "one elevated card per file" pattern while keeping M3 separators.
class _FlatFileGroup extends StatelessWidget {
  final List<FileEntry> entries;
  final bool selecting;
  final Uint8List? Function(FileEntry entry) thumbnailFor;
  final bool Function(String path) isSelected;
  final GlobalKey Function(String path) keyFor;
  final ValueChanged<FileEntry> onOpen;
  final ValueChanged<FileEntry> onLongPress;
  final ValueChanged<String> onToggleSelect;
  final ValueChanged<FileEntry> onMore;
  final ValueChanged<FileEntry> onSecondaryTap;
  final ValueChanged<FileEntry> onHoverEnter;
  final VoidCallback onHoverExit;

  const _FlatFileGroup({
    required this.entries,
    required this.selecting,
    required this.thumbnailFor,
    required this.isSelected,
    required this.keyFor,
    required this.onOpen,
    required this.onLongPress,
    required this.onToggleSelect,
    required this.onMore,
    required this.onSecondaryTap,
    required this.onHoverEnter,
    required this.onHoverExit,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < entries.length; index++) ...[
          NexaFileTile(
            key: keyFor(entries[index].path),
            entry: entries[index],
            thumbnail: thumbnailFor(entries[index]),
            selected: isSelected(entries[index].path),
            selecting: selecting,
            onTap: onOpen,
            onLongPress: () => onLongPress(entries[index]),
            onSecondaryTap: onSecondaryTap,
            onHoverEnter: onHoverEnter,
            onHoverExit: onHoverExit,
            onSelectToggle: () => onToggleSelect(entries[index].path),
            trailing: selecting
                ? null
                : IconButton(
                    tooltip: 'More options',
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                    onPressed: () => onMore(entries[index]),
                  ),
          ),
          if (index < entries.length - 1)
            Divider(
              height: 1,
              indent: AppDimens.rowInset +
                  (selecting
                      ? AppDimens.touchTarget + AppDimens.space4
                      : AppDimens.iconMedium) +
                  AppDimens.iconTile +
                  AppDimens.space16,
              endIndent: AppDimens.rowInset,
              color: scheme.outlineVariant,
            ),
        ],
      ],
    );
  }
}

class _HoverPreview extends StatelessWidget {
  final FileEntry entry;
  final Uint8List? thumbnail;

  const _HoverPreview({required this.entry, required this.thumbnail});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NexaSurface(
      level: NexaSurfaceLevel.floating,
      radius: AppDimens.radiusMedium,
      padding: const EdgeInsets.all(AppDimens.space12),
      child: SizedBox(
        width: 220,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppDimens.radiusSmall),
              child: SizedBox(
                width: AppDimens.iconTileLarge,
                height: AppDimens.iconTileLarge,
                child: thumbnail != null
                    ? Image.memory(thumbnail!, fit: BoxFit.cover)
                    : entry.isFolder
                        ? NexaFileGlyph.folder(size: AppDimens.iconTileLarge)
                        : NexaFileGlyph(
                            name: entry.name,
                            type: entry.type,
                            size: AppDimens.iconTileLarge,
                          ),
              ),
            ),
            const SizedBox(width: AppDimens.space12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.titleSmall.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppDimens.space2),
                  Text(
                    '${FileKind.label(entry.category)} · ${Format.bytes(entry.size)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.bodySmall.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  const _StickyHeaderDelegate({required this.child});

  @override
  double get minExtent => 52;

  @override
  double get maxExtent => 52;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) =>
      SizedBox.expand(child: child);

  @override
  bool shouldRebuild(covariant _StickyHeaderDelegate oldDelegate) =>
      oldDelegate.child != child;
}

class _GroupHeader extends StatelessWidget {
  final String title;
  final int count;

  const _GroupHeader(this.title, {required this.count});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.rowInset,
        AppDimens.space20,
        AppDimens.rowInset,
        AppDimens.space8,
      ),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: AppTextStyle.sectionHeader.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppDimens.space8),
          Text(
            '$count',
            style: AppTextStyle.labelSmall.copyWith(
              color: scheme.onSurfaceVariant,
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
    final scheme = Theme.of(context).colorScheme;
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
              style: AppTextStyle.bodySmall.copyWith(
                color: scheme.onSurfaceVariant,
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
              style: AppTextStyle.bodyMedium.copyWith(color: scheme.onSurface),
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
  final ValueChanged<_FileFilter> onChanged;

  const _FileFilterBar({
    required this.selected,
    required this.folderCount,
    required this.fileCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.pageMargin),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  SizedBox(
                    height: AppDimens.touchTarget,
                    child: FilterChip(
                      label: Text('All ${folderCount + fileCount}'),
                      selected: selected == _FileFilter.all,
                      onSelected: (_) => onChanged(_FileFilter.all),
                      showCheckmark: false,
                    ),
                  ),
                  const SizedBox(width: AppDimens.space6),
                  SizedBox(
                    height: AppDimens.touchTarget,
                    child: FilterChip(
                      label: Text('Folders $folderCount'),
                      selected: selected == _FileFilter.folders,
                      onSelected: (_) => onChanged(_FileFilter.folders),
                      showCheckmark: false,
                    ),
                  ),
                  const SizedBox(width: AppDimens.space6),
                  SizedBox(
                    height: AppDimens.touchTarget,
                    child: FilterChip(
                      label: Text('Files $fileCount'),
                      selected: selected == _FileFilter.files,
                      onSelected: (_) => onChanged(_FileFilter.files),
                      showCheckmark: false,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
