import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_haptics.dart';
import '../../../core/design/app_motion.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/models/file_entry.dart';
import '../../../core/utils/file_kind.dart';
import '../../../core/utils/format.dart';
import '../../../services/api.dart';
import '../../../services/image_pipeline.dart';
import '../../../services/session.dart';
import '../../../services/thumbnail_cache.dart';
import '../../../services/trash_restore.dart';
import '../../navigation/file_opener.dart';
import '../../widgets/nexa_components.dart';
import '../files/file_share_sheet.dart';
import 'photo_viewer.dart';

/// How many thumbnails are fetched eagerly after listing loads. The grid
/// fetches the rest lazily as tiles scroll into view.
const int _eagerThumbCount = 24;

enum _PhotosMenuAction { layout, refresh }

class PhotosScreen extends StatefulWidget {
  final Api api;
  final Session session;
  final ValueChanged<bool>? onSelectionChanged;

  const PhotosScreen({
    super.key,
    required this.api,
    required this.session,
    this.onSelectionChanged,
  });

  @override
  State<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends State<PhotosScreen> {
  List<Map<String, dynamic>> _photos = [];
  late final ImageRepository _images = ImageRepository(widget.api);

  /// Paths whose format the server cannot thumbnail (e.g. HEIC without a
  /// codec). The grid shows a graceful placeholder instead of pulling the
  /// full-resolution original into memory for every cell.
  final Set<String> _noThumbnail = <String>{};

  final Set<String> _loadingThumbs = <String>{};
  bool _loading = true;
  String? _error;

  /// Month buckets, newest first, computed once per listing.
  ///
  /// Grouping sorts every photo, and the grid rebuilds on each thumbnail that
  /// arrives — recomputing it in `build` made scrolling a large library
  /// O(n log n) per thumbnail. Cached here instead.
  List<(String, List<int>)> _groups = const [];

  /// The month-grouped order actually painted on screen. Range selection
  /// follows this list, not storage order, so a drag matches the visible run.
  List<int> _visualOrder = const [];

  /// Storage index -> visible index. Pointer moves happen many times per drag,
  /// so resolving the visual position must not scan the library each frame.
  Map<int, int> _visualIndexByPhotoIndex = const {};

  /// `path -> index`, so the viewer's placeholder lookup is O(1) per build
  /// instead of a linear scan of the whole library.
  Map<String, int> _indexByPath = const {};

  /// Cached media category per path so the grid never re-parses filenames on
  /// every thumbnail rebuild.
  Map<String, Category> _categoryByPath = const {};

  bool _selecting = false;
  final Set<String> _selected = <String>{};
  int _gridColumns = 3;
  int? _activePointer;
  Offset? _lastPointerPosition;
  bool _dragSelecting = false;
  int? _dragAnchorIndex;
  Set<String> _dragBaseSelection = const <String>{};

  /// Keeps a range drag alive when the pointer reaches the viewport edge.
  /// Flutter owns the frame loop and clamps at both scroll extents, so this is
  /// interruptible the instant the pointer moves away or the drag ends.
  EdgeDraggingAutoScroller? _selectionAutoScroller;
  static const double _autoScrollEdge = AppDimens.space48;
  static const double _autoScrollVelocity = 24;

  /// The last cell the drag tip reached. Range selection fires one haptic per
  /// newly reached cell, not one per pointer move.
  int? _dragLastIndex;

  /// Visual grid position used by desktop arrow-key range extension. Reuses
  /// the drag anchor/base so keyboard and pointer ranges settle identically.
  int? _keyboardAnchorIndex;

  /// Keeps shortcuts scoped to selection mode while still receiving events
  /// bubbled from the contextual bar's chips.
  final FocusNode _selectionFocusNode = FocusNode(
    debugLabel: 'photos-selection',
  );

  double? _pinchBaseColumns;
  final Map<String, GlobalKey> _cellKeys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _attachDiskCache();
    _loadGridColumns();
    load();
  }

  @override
  void dispose() {
    _selectionAutoScroller?.stopAutoScroll();
    _selectionFocusNode.dispose();
    super.dispose();
  }

  static const _gridColumnsPreference = 'nexadrive.photos.grid_columns';

  Future<void> _loadGridColumns() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_gridColumnsPreference);
      if (saved != null && mounted) {
        setState(() => _gridColumns = NexaGridLayout.clamp(saved));
      }
    } catch (_) {
      // A missing preference store does not prevent browsing.
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

  Future<void> _showGridDensityPicker() async {
    final selected = await showNexaGridLayoutPicker(
      context: context,
      columns: _gridColumns,
      title: 'Gallery layout',
      subtitle: 'Choose how many photos fit across the grid.',
    );
    if (selected == null || !mounted || selected == _gridColumns) return;
    setState(() => _gridColumns = selected);
    await _saveGridColumns(selected);
  }

  GlobalKey _keyForCell(String path) =>
      _cellKeys.putIfAbsent(path, () => GlobalKey());

  void _pruneCellKeys() {
    _cellKeys.removeWhere((_, key) => key.currentContext == null);
  }

  void _onPointerDown(PointerDownEvent event) {
    _activePointer = event.pointer;
    _lastPointerPosition = event.position;
  }

  void _onPointerMove(PointerMoveEvent event) {
    _lastPointerPosition = event.position;
    if (!_dragSelecting || event.pointer != _activePointer) return;
    _selectAtLastPointer();
    _updateSelectionAutoScroll(event.position);
  }

  void _onPointerUp(PointerEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    _lastPointerPosition = null;
    _dragSelecting = false;
    _dragAnchorIndex = null;
    _dragBaseSelection = const <String>{};
    _dragLastIndex = null;
    _selectionAutoScroller?.stopAutoScroll();
  }

  /// Applies the visible range at the last known pointer position. Reused by
  /// the auto-scroller so content moving under a still finger keeps selecting.
  void _selectAtLastPointer() {
    if (!mounted || !_dragSelecting) return;
    final position = _lastPointerPosition;
    if (position == null) return;
    final path = _pathAtPosition(position);
    if (path == null) return;
    final index = _indexByPath[path];
    if (index == null) return;
    final visual = _visualIndexOf(index);
    if (visual < 0 || visual == _dragLastIndex) return;
    _dragLastIndex = visual;
    if (_selectRangeTo(visual)) AppHaptics.selection();
  }

  void _updateSelectionAutoScroll(Offset position) {
    if (!_dragSelecting || !mounted) return;
    final scroller = _selectionAutoScroller;
    if (scroller != null && !scroller.scrollable.mounted) {
      _selectionAutoScroller = null;
      return;
    }
    scroller?.startAutoScrollIfNecessary(
      Rect.fromCircle(center: position, radius: _autoScrollEdge),
    );
  }

  void _bindSelectionAutoScroll(String path, Offset position) {
    if (!mounted) return;
    final scrollable = _keyForCell(path)
        .currentContext
        ?.findAncestorStateOfType<ScrollableState>();
    if (scrollable == null || !scrollable.mounted) return;
    final existing = _selectionAutoScroller;
    if (existing?.scrollable == scrollable) {
      _updateSelectionAutoScroll(position);
      return;
    }
    existing?.stopAutoScroll();
    _selectionAutoScroller = EdgeDraggingAutoScroller(
      scrollable,
      velocityScalar: _autoScrollVelocity,
      onScrollViewScrolled: () {
        _selectAtLastPointer();
        // The helper caches the target relative to the scroll origin. Refresh
        // it each step so a stationary finger keeps scrolling instead of
        // falling out of range after the first increment.
        final position = _lastPointerPosition;
        if (position != null) _updateSelectionAutoScroll(position);
      },
    );
    _updateSelectionAutoScroll(position);
  }

  void _onScaleStart(ScaleStartDetails details) {
    // Cheap early capture when the recognizer happens to accept with two
    // fingers. The common one-finger accept is handled lazily in _onScaleUpdate.
    if (details.pointerCount == 2) {
      _pinchBaseColumns = _gridColumns.toDouble();
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount < 2 || _dragSelecting) return;
    var base = _pinchBaseColumns;
    if (base == null) {
      // Flutter's scale recognizer normally accepts with a single pointer, so
      // onScaleStart rarely sees two. Capture the base on the first genuine
      // two-finger update instead, or the pinch never engages at all.
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

  void _beginDragSelection(int index, Offset globalPosition) {
    final visualAnchor = _visualIndexOf(index);
    if (visualAnchor < 0) return;
    if (!_selecting) {
      // Entering multi-select gets one firm impact. From there the drag only
      // clicks when the tip reaches a *different* cell (see _onPointerMove),
      // so feedback tracks selections rather than pointer pixels.
      AppHaptics.impact();
      _dragBaseSelection = <String>{_pathAtVisual(visualAnchor)};
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
    _dragAnchorIndex = visualAnchor;
    _dragSelecting = true;
    _keyboardAnchorIndex = null;
    _lastPointerPosition = globalPosition;
    // Entering selection rewraps the page in a Focus node, which rebuilds the
    // scroll view. Bind only after that frame so the scroller is still mounted.
    final anchorPath = _pathAtVisual(visualAnchor);
    final pointer = _activePointer;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_dragSelecting || _activePointer != pointer) return;
      _bindSelectionAutoScroll(anchorPath, globalPosition);
    });
    final hit = _pathAtPosition(globalPosition);
    final hitIndex = hit == null ? null : _indexByPath[hit];
    final target = hitIndex == null ? visualAnchor : _visualIndexOf(hitIndex);
    _dragLastIndex = target;
    _selectRangeTo(target);
  }

  int _visualIndexOf(int photoIndex) =>
      _visualIndexByPhotoIndex[photoIndex] ?? -1;

  String _pathAtVisual(int visualIndex) => _pathAt(_visualOrder[visualIndex]);

  /// Selects the whole run between the long-press anchor and [index], the way
  /// a phone gallery turns one drag into a range selection. Indices here are
  /// visual positions in the month-grouped grid. Returns whether the visible
  /// selection actually changed, so callers can time a single haptic.
  bool _selectRangeTo(int index) {
    final anchor = _dragAnchorIndex;
    if (anchor == null || index < 0 || index >= _visualOrder.length) {
      return false;
    }
    final start = index < anchor ? index : anchor;
    final end = index < anchor ? anchor : index;
    final next = <String>{..._dragBaseSelection};
    for (var i = start; i <= end; i++) {
      next.add(_pathAtVisual(i));
    }
    if (next.length == _selected.length && next.every(_selected.contains)) {
      return false;
    }
    setState(() {
      _selected
        ..clear()
        ..addAll(next);
    });
    return true;
  }

  String? _pathAtPosition(Offset globalPosition) {
    String? hitPath;
    final stale = <String>[];
    for (final entry in _cellKeys.entries) {
      final renderObject = entry.value.currentContext?.findRenderObject();
      if (renderObject is! RenderBox ||
          !renderObject.attached ||
          !renderObject.hasSize) {
        stale.add(entry.key);
        continue;
      }
      final rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
      if (rect.contains(globalPosition)) {
        hitPath = entry.key;
      }
    }
    for (final path in stale) {
      _cellKeys.remove(path);
    }
    return hitPath;
  }

  /// The disk cache lets previews survive a restart. It is keyed by server +
  /// path + rendition, so it can never serve an original.
  Future<void> _attachDiskCache() async {
    try {
      final cache = await ThumbnailCache.open();
      if (!mounted) return;
      _images.diskCache = cache;
      setState(() {});
    } catch (_) {
      // A cache-less run is still fully functional.
    }
  }

  Future<void> load() async {
    setState(() {
      _loading = true;
      _error = null;
      _noThumbnail.clear();
    });
    try {
      // `/api/photos` stays authoritative for images. Videos and PDFs are
      // discovered with the existing file browser API so this works against
      // current servers without changing their contract.
      final photos = await widget.api.photos();
      if (!mounted) return;
      final images = photos.map(_asFileRow).toList(growable: false);
      final extra = await _discoverMedia(
        knownPaths: images.map(_pathOf).toSet(),
      );
      if (!mounted) return;
      setState(() {
        _photos = [...images, ...extra];
        _reindex();
        _loading = false;
      });
      _prefetch();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e);
        _loading = false;
      });
    }
  }

  /// Rebuilds the derived month buckets, the path index and media categories.
  void _reindex() {
    _indexByPath = {
      for (var i = 0; i < _photos.length; i++) _pathAt(i): i,
    };
    _categoryByPath = {
      for (final row in _photos) _pathOf(row): FileEntry.fromJson(row).category,
    };
    _groups = _computeGroups();
    _visualOrder = _groups.expand((group) => group.$2).toList(growable: false);
    _visualIndexByPhotoIndex = {
      for (var i = 0; i < _visualOrder.length; i++) _visualOrder[i]: i,
    };
  }

  String _pathOf(Map<String, dynamic> row) => (row['path'] ?? '').toString();

  /// Normalizes legacy photo rows into file-shaped JSON so one media picker
  /// can drive thumbnails, sharing and the existing file viewers.
  Map<String, dynamic> _asFileRow(Map<String, dynamic> row) =>
      <String, dynamic>{...row, 'type': 'file'};

  /// Best-effort scan for video and PDF files using the existing browse API.
  ///
  /// A failed directory is skipped rather than failing the whole gallery; a
  /// bounded breadth-first walk keeps very large accounts responsive.
  Future<List<Map<String, dynamic>>> _discoverMedia({
    required Set<String> knownPaths,
  }) async {
    const maxDirectories = 80;
    const maxDepth = 6;
    const maxResults = 600;

    final queue = <_BrowseTarget>[const _BrowseTarget('', 0)];
    final visited = <String>{};
    final found = <Map<String, dynamic>>[];

    while (queue.isNotEmpty &&
        visited.length < maxDirectories &&
        found.length < maxResults) {
      final target = queue.removeAt(0);
      if (!visited.add(target.path)) continue;

      try {
        final entries = await widget.api.listFiles(target.path);
        for (final json in entries) {
          final entry = FileEntry.fromJson(json);
          if (entry.isFolder) {
            if (target.depth < maxDepth) {
              queue.add(_BrowseTarget(entry.path, target.depth + 1));
            }
            continue;
          }
          if (entry.category != Category.video &&
              entry.category != Category.pdf) {
            continue;
          }
          if (!knownPaths.add(entry.path)) continue;
          found.add(_asFileRow(json));
          if (found.length >= maxResults) break;
        }
      } catch (_) {
        // One unreadable folder must not hide the rest of the library.
      }
    }
    return found;
  }

  bool _isImageAt(int index) =>
      _categoryByPath[_pathAt(index)] == Category.image;

  Category _categoryAt(int index) =>
      _categoryByPath[_pathAt(index)] ?? Category.unknown;

  String _mediaLabel(Category category) => switch (category) {
        Category.video => 'Video',
        Category.pdf => 'PDF',
        _ => 'Photo',
      };

  void _prefetch() {
    for (var i = 0; i < _photos.length && i < _eagerThumbCount; i++) {
      _ensureThumb(_images, i);
    }
  }

  ImageKey _thumbKey(int index, {int max = 512}) => ImageRepository.keyFor(
        _photos[index],
        namespace: widget.session.cacheNamespace,
        rendition: ImageRendition.thumbnail,
        maxEdge: max,
      );

  Future<void> _ensureThumb(ImageRepository pipeline, int index) async {
    if (index < 0 || index >= _photos.length) return;
    final key = _thumbKey(index);
    final path = key.path;
    if (pipeline.peekThumbnail(key) != null) return;
    if (_noThumbnail.contains(path) || _loadingThumbs.contains(path)) return;
    _loadingThumbs.add(path);
    try {
      await pipeline.thumbnail(key, max: 512);
      if (mounted) setState(() {});
    } on ThumbnailUnavailable {
      // Render the format placeholder — never substitute a different
      // rendition for the preview.
      if (mounted) setState(() => _noThumbnail.add(path));
    } catch (_) {
      // Transient failures leave the placeholder; scrolling retries.
    } finally {
      _loadingThumbs.remove(path);
    }
  }

  String _friendlyError(Object e) {
    if (e is ApiException) {
      if (e.status == 401) return 'Your session expired. Sign in again.';
      if (e.status >= 500) return 'The server couldn’t list your photos.';
      return e.message;
    }
    return 'Check your connection and try again.';
  }

  Future<void> _open(int index) async {
    final row = _photos[index];
    final entry = FileEntry.fromJson(row);

    // Video and PDF share the exact viewers used everywhere else in the app.
    if (entry.category != Category.image) {
      await FileOpener.open(context, api: widget.api, entry: entry);
      return;
    }

    // The image viewer only receives images, so swiping never lands on a PDF
    // or video tile that cannot be rendered by PhotoViewer.
    final images = <Map<String, dynamic>>[];
    var initialIndex = 0;
    for (var i = 0; i < _photos.length; i++) {
      if (!_isImageAt(i)) continue;
      if (_pathAt(i) == entry.path) initialIndex = images.length;
      images.add(_photos[i]);
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoViewer(
          photos: images,
          initialIndex: initialIndex,
          api: widget.api,
          images: _images,
          // The grid's own thumbnail is offered as the blurred loading
          // backdrop only, so the viewer never has to fetch one.
          thumbnailLookup: (path) {
            final i = _indexByPath[path];
            if (i == null) return null;
            return _images.peekThumbnail(_thumbKey(i));
          },
          onDeleted: (path) {
            if (!mounted) return;
            setState(() {
              _photos.removeWhere((p) => p['path'] == path);
              _reindex();
            });
          },
        ),
      ),
    );
  }

  // ------------------------------------------------------------ selection
  void _onCellTap(int index) {
    if (_shortcutsBlocked()) return;
    final toggle = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final extend = HardwareKeyboard.instance.isShiftPressed;
    if (!_selecting && !toggle && !extend) {
      _open(index);
      return;
    }
    final visual = _visualIndexOf(index);
    if (visual < 0) return;

    if (!_selecting) {
      AppHaptics.impact();
      setState(() => _selecting = true);
      widget.onSelectionChanged?.call(true);
    }
    if (extend) {
      final anchor = (_dragAnchorIndex ?? _keyboardAnchorIndex ?? visual)
          .clamp(0, _visualOrder.length - 1);
      _dragBaseSelection = Set<String>.from(_selected);
      _dragAnchorIndex = anchor;
      _keyboardAnchorIndex = anchor;
      if (_selectRangeTo(visual)) AppHaptics.selection();
      return;
    }

    _toggleSelect(index);
    if (toggle) {
      // A modifier tap establishes a new range anchor; a plain tap only flips
      // the item and leaves the previous anchor alone.
      _dragAnchorIndex = visual;
      _keyboardAnchorIndex = visual;
      _dragBaseSelection = <String>{_pathAtVisual(visual)};
    }
  }

  bool _shortcutsBlocked() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return false;
    final focused = focus.context?.widget;
    return focused is EditableText || focused is TextField;
  }

  void _onCellLongPress(int index, Offset globalPosition) {
    _beginDragSelection(index, globalPosition);
  }

  void _toggleSelect(int index) {
    final path = _pathAt(index);
    AppHaptics.selection();
    _keyboardAnchorIndex = null;
    setState(() {
      if (_selected.contains(path)) {
        _selected.remove(path);
      } else {
        _selected.add(path);
      }
    });
  }

  /// Chips toggle between "all" and "clear"; Ctrl/Cmd+A is always "all".
  void _toggleSelectAll() {
    AppHaptics.selection();
    if (_visualOrder.isNotEmpty && _selected.length == _visualOrder.length) {
      _exitSelection();
      return;
    }
    _selectAllVisible();
  }

  void _selectAllVisible() {
    if (_visualOrder.isEmpty) return;
    setState(() {
      _selecting = true;
      _selected
        ..clear()
        ..addAll(_visualOrder.map(_pathAtVisual));
    });
    _keyboardAnchorIndex = null;
    _dragAnchorIndex = null;
    _dragBaseSelection = const <String>{};
    widget.onSelectionChanged?.call(true);
  }

  /// Selects the visible run from the current range anchor (or the first
  /// selected cell, or the top of the month-ordered grid) to the very end.
  void _selectAllFromHere() {
    if (_visualOrder.isEmpty) return;
    AppHaptics.selection();
    final explicit = _keyboardAnchorIndex ?? _dragAnchorIndex;
    final fromSelected = _selected.isEmpty
        ? -1
        : _visualIndexOf(_indexByPath[_selected.first] ?? -1);
    final anchor = explicit ?? fromSelected;
    final start = (anchor >= 0 ? anchor : 0).clamp(0, _visualOrder.length - 1);
    setState(() {
      _selecting = true;
      _selected
        ..clear()
        ..addAll(
          List<String>.generate(
            _visualOrder.length - start,
            (i) => _pathAtVisual(start + i),
          ),
        );
    });
    _keyboardAnchorIndex = start;
    _dragAnchorIndex = start;
    _dragBaseSelection = Set<String>.from(_selected);
    widget.onSelectionChanged?.call(true);
  }

  // ------------------------------------------------------------- keyboard
  bool _focusIsTextEntry() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    // Text fields and dialogs own their own focus scopes; let them keep keys.
    return context.findAncestorWidgetOfExactType<EditableText>() != null ||
        context.findAncestorWidgetOfExactType<Dialog>() != null;
  }

  KeyEventResult _onSelectionKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_focusIsTextEntry()) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final command = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    if (command && key == LogicalKeyboardKey.keyA) {
      _selectAllVisible();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (!_selecting) return KeyEventResult.ignored;
      _exitSelection();
      return KeyEventResult.handled;
    }
    if (!_selecting || _visualOrder.isEmpty) return KeyEventResult.ignored;

    final step = switch (key) {
      LogicalKeyboardKey.arrowLeft => -1,
      LogicalKeyboardKey.arrowRight => 1,
      LogicalKeyboardKey.arrowUp => -_gridColumns,
      LogicalKeyboardKey.arrowDown => _gridColumns,
      _ => null,
    };
    if (step == null) return KeyEventResult.ignored;
    _extendSelectionByKeyboard(step);
    return KeyEventResult.handled;
  }

  /// Arrow keys walk the month-ordered grid and extend a contiguous run, the
  /// keyboard twin of the drag anchor. The first press plants the anchor; later
  /// presses move it and click once per newly reached cell.
  void _extendSelectionByKeyboard(int step) {
    final current = _keyboardAnchorIndex;
    if (current == null || current >= _visualOrder.length) {
      final fromSelected = _selected.isEmpty
          ? -1
          : _visualIndexOf(_indexByPath[_selected.first] ?? -1);
      final start = (fromSelected >= 0 ? fromSelected : 0).clamp(
        0,
        _visualOrder.length - 1,
      );
      _keyboardAnchorIndex = start;
      _dragAnchorIndex = start;
      _dragBaseSelection = Set<String>.from(_selected);
      _dragLastIndex = start;
      if (_selected.isEmpty) {
        setState(() => _selected.add(_pathAtVisual(start)));
      }
      AppHaptics.selection();
      _revealVisualIndex(start);
      return;
    }

    final next = (current + step).clamp(0, _visualOrder.length - 1);
    if (next == current) return;
    _keyboardAnchorIndex = next;
    _dragAnchorIndex = next;
    _dragLastIndex = next;
    _selectRangeTo(next);
    AppHaptics.selection();
    _revealVisualIndex(next);
  }

  void _revealVisualIndex(int visualIndex) {
    if (visualIndex < 0 || visualIndex >= _visualOrder.length) return;
    final context = _cellKeys[_pathAtVisual(visualIndex)]?.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: AppMotion.resolve(context, AppMotion.fast),
      curve: AppMotion.curveFor(context, AppMotion.standard),
      alignment: 0.5,
    );
  }

  String _pathAt(int index) => (_photos[index]['path'] ?? '').toString();

  Future<void> _deleteSelected() async {
    final count = _selected.length;
    final confirm = await showNexaConfirmation(
      context: context,
      title: 'Move to Trash',
      message:
          count == 1 ? 'Move 1 item to trash?' : 'Move $count items to trash?',
      confirmText: 'Trash',
      isDestructive: true,
    );
    if (confirm != true || !mounted) return;
    final removed = _selected.toList();
    try {
      await widget.api.batch(action: 'delete', paths: removed);
      _exitSelection();
      if (!mounted) return;
      setState(() {
        _photos.removeWhere((p) => removed.contains(p['path']));
        _reindex();
      });
      NexaUndo.show(
        context,
        '${Format.count(removed.length, 'item')} moved to Trash',
        onAction: () => unawaited(_undoTrash(removed)),
      );
    } catch (e) {
      if (mounted) _toast(_friendlyError(e));
    }
  }

  /// Resolves the freshly created trash ids and restores them, then refreshes
  /// the gallery so both this tab and the rest of the app agree on state.
  Future<void> _undoTrash(List<String> paths) async {
    try {
      await TrashRestore.paths(widget.api, paths);
      if (!mounted) return;
      await load();
      if (!mounted) return;
      _toast('Back in your gallery');
    } catch (e) {
      if (!mounted) return;
      _toast(
        e is StateError
            ? e.message
            : 'That restore didn’t finish. Check your connection and try again.',
      );
    }
  }

  Future<void> _shareSelected() async {
    final entries = _photos
        .where((p) => _selected.contains(p['path']))
        .map(FileEntry.fromJson)
        .toList();
    if (entries.isEmpty) return;
    if (!mounted) return;
    await showNexaFormSheet<void>(
      context,
      builder: (_) => FileShareSheet(api: widget.api, files: entries),
    );
    if (mounted) _exitSelection();
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
    _dragSelecting = false;
    _activePointer = null;
    _dragAnchorIndex = null;
    _dragBaseSelection = const <String>{};
    _dragLastIndex = null;
    _keyboardAnchorIndex = null;
    widget.onSelectionChanged?.call(false);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // -------------------------------------------------------------- grouping
  /// Photos newest-first, grouped into month buckets.
  List<(String, List<int>)> _computeGroups() {
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    final order = List<int>.generate(_photos.length, (i) => i);
    order.sort((a, b) {
      final da = _modifiedAt(_photos[a]) ?? epoch;
      final db = _modifiedAt(_photos[b]) ?? epoch;
      return db.compareTo(da);
    });
    final buckets = <String, List<int>>{};
    for (final i in order) {
      final t = _modifiedAt(_photos[i]);
      final key = t == null ? 'Unknown date' : _monthLabel(t.toLocal());
      buckets.putIfAbsent(key, () => <int>[]).add(i);
    }
    return buckets.entries.map((e) => (e.key, e.value)).toList(growable: false);
  }

  DateTime? _modifiedAt(Map<String, dynamic> photo) =>
      DateTime.tryParse(photo['modified_at']?.toString() ?? '');

  String _monthLabel(DateTime t) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[t.month - 1]} ${t.year}';
  }

  @override
  Widget build(BuildContext context) {
    final photoCount = _photos.length;

    Widget page = NexaPage(
      title: 'Photos',
      bottomSafeArea: false,
      subtitle: _selecting
          ? 'Drag to select · Tap to refine · Arrows extend'
          : photoCount == 0
              ? 'Photos, videos and PDFs in one place'
              : Format.count(photoCount, 'item'),
      headerAction: _selecting
          ? null
          : PopupMenuButton<_PhotosMenuAction>(
              tooltip: 'Gallery options',
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (action) {
                switch (action) {
                  case _PhotosMenuAction.layout:
                    _showGridDensityPicker();
                  case _PhotosMenuAction.refresh:
                    load();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _PhotosMenuAction.layout,
                  child: Text('Gallery layout'),
                ),
                PopupMenuItem(
                  value: _PhotosMenuAction.refresh,
                  child: Text('Refresh library'),
                ),
              ],
            ),
      body: _body(),
    );

    // Shortcuts live only while selecting; key events from the bar's chips
    // bubble up to this node, while dialogs/text fields keep their own focus.
    if (_selecting) {
      page = Focus(
        focusNode: _selectionFocusNode,
        autofocus: true,
        onKeyEvent: _onSelectionKey,
        child: page,
      );
    }

    // The contextual bar floats over the grid. Tracking at this level keeps a
    // range drag alive when the finger reaches the bottom edge over that bar.
    page = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerUp,
      child: page,
    );

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting) _exitSelection();
      },
      child: page,
    );
  }

  /// The body, cross-faded between states so a resolved library settles in.
  Widget _body() => NexaStateSwitcher(
        stateKey: ValueKey(_bodyState),
        child: _buildBody(),
      );

  String get _bodyState => _loading
      ? 'loading'
      : _error != null
          ? 'error'
          : _photos.isEmpty
              ? 'empty'
              : 'content';

  Widget _buildBody() {
    if (_loading) {
      return const NexaLoadingBlock();
    }
    if (_error != null) {
      return NexaEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'That didn’t load — try again',
        hint: _error,
        actionLabel: 'Retry',
        onAction: load,
        actionIcon: Icons.refresh_rounded,
        iconSize: AppDimens.iconTile,
      );
    }
    if (_photos.isEmpty) {
      return NexaEmptyState(
        icon: Icons.photo_library_outlined,
        title: 'Nothing here yet',
        hint:
            'Photos, videos and PDFs you add will show up here. Upload from My files to get started.',
        actionLabel: 'Refresh',
        onAction: load,
        actionIcon: Icons.refresh_rounded,
        iconSize: AppDimens.iconTile,
      );
    }

    final groups = _groups;
    final bottomClearance =
        _selecting ? AppDimens.space24 : MediaQuery.paddingOf(context).bottom;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final contentWidth = (viewportWidth - AppDimens.pageMargin * 2)
        .clamp(80.0, AppDimens.contentMaxWidth);
    final tileWidth =
        (contentWidth - AppDimens.space2 * (_gridColumns - 1)) / _gridColumns;
    final decodeWidth =
        (tileWidth * MediaQuery.devicePixelRatioOf(context)).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: load,
            child: GestureDetector(
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              child: NotificationListener<ScrollNotification>(
                onNotification: (_) {
                  _pruneCellKeys();
                  return false;
                },
                child: CustomScrollView(
                  slivers: [
                    for (final (label, indices) in groups) ...[
                      SliverToBoxAdapter(
                        child:
                            _MonthHeader(label: label, count: indices.length),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDimens.space2,
                        ),
                        sliver: SliverGrid.builder(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: _gridColumns,
                            mainAxisSpacing: AppDimens.space2,
                            crossAxisSpacing: AppDimens.space2,
                            childAspectRatio: 1,
                          ),
                          itemCount: indices.length,
                          itemBuilder: (context, i) {
                            final index = indices[i];
                            final path = _pathAt(index);
                            return _PhotoCell(
                              key: _keyForCell(path),
                              bytes: _thumbBytes(index),
                              decodeWidth: decodeWidth,
                              category: _categoryAt(index),
                              unavailable: _noThumbnail.contains(path),
                              name: _photos[index]['name']?.toString() ?? path,
                              semanticLabel:
                                  '${_mediaLabel(_categoryAt(index))}: '
                                  '${_photos[index]['name'] ?? path}',
                              heroTag: 'photo:$path',
                              selected: _selected.contains(path),
                              selecting: _selecting,
                              onTap: () => _onCellTap(index),
                              onLongPressStart: (position) =>
                                  _onCellLongPress(index, position),
                              onVisible: () => _ensureThumb(_images, index),
                            );
                          },
                        ),
                      ),
                      const SliverToBoxAdapter(
                        child: SizedBox(height: AppDimens.space16),
                      ),
                    ],
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: bottomClearance > AppDimens.space24
                            ? bottomClearance
                            : AppDimens.space24,
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
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppDimens.pageMargin,
              AppDimens.space4,
              AppDimens.pageMargin,
              nexaContextualBarBottomPadding(context) + AppDimens.space4,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: NexaSurface(
                  level: NexaSurfaceLevel.floating,
                  radius: AppDimens.radiusMedium,
                  padding: const EdgeInsets.fromLTRB(
                    AppDimens.space8,
                    AppDimens.space6,
                    AppDimens.space8,
                    AppDimens.space6,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          _SelectionCount(count: _selected.length),
                          const SizedBox(width: AppDimens.space8),
                          Expanded(
                            child: Text(
                              'Selected',
                              style: AppTextStyle.titleMedium.copyWith(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                          NexaIconActionItem(
                            icon: Icons.close_rounded,
                            tooltip: 'Cancel selection',
                            onTap: _exitSelection,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppDimens.space4),
                      // Wrapping keeps every action reachable on narrow
                      // phones instead of hiding the destructive one in a
                      // horizontal scroller.
                      Wrap(
                        spacing: AppDimens.space6,
                        runSpacing: AppDimens.space2,
                        children: [
                          NexaActionItem(
                            icon: Icons.select_all_rounded,
                            label: 'Select all from here',
                            onTap: _selectAllFromHere,
                          ),
                          Tooltip(
                            message: _selected.length == _visualOrder.length
                                ? 'Clear selection'
                                : 'Select all',
                            child: NexaActionItem(
                              icon: _selected.length == _visualOrder.length
                                  ? Icons.deselect_rounded
                                  : Icons.done_all_rounded,
                              label: _selected.length == _visualOrder.length
                                  ? 'Clear'
                                  : 'All',
                              onTap: _toggleSelectAll,
                            ),
                          ),
                          NexaActionItem(
                            icon: Icons.share_outlined,
                            label: 'Share',
                            enabled: _selected.isNotEmpty,
                            onTap: _shareSelected,
                          ),
                          Tooltip(
                            message: 'Move selected items to Trash',
                            child: NexaActionItem(
                              icon: Icons.delete_outline_rounded,
                              label: 'Move to trash',
                              enabled: _selected.isNotEmpty,
                              onTap: _deleteSelected,
                              isDestructive: true,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Uint8List? _thumbBytes(int index) {
    if (_noThumbnail.contains(_pathAt(index))) {
      return null;
    }
    return _images.peekThumbnail(_thumbKey(index));
  }
}

/// The selection count springs in whenever the run grows or shrinks. A short
/// ease-out-back overshoot reads as a detent; reduced motion gets an instant
/// swap through [AppMotion.resolve].
class _SelectionCount extends StatelessWidget {
  final int count;

  const _SelectionCount({required this.count});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final duration = AppMotion.resolve(context, AppMotion.fast);
    final reduced = AppMotion.reducedMotion(context);

    return AnimatedSwitcher(
      duration: duration,
      reverseDuration: duration,
      switchInCurve: reduced ? Curves.linear : Curves.easeOutBack,
      switchOutCurve: reduced ? Curves.linear : Curves.easeIn,
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: animation,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: DecoratedBox(
        key: ValueKey<int>(count),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.space8,
            vertical: AppDimens.space4,
          ),
          child: Text(
            Format.count(count, 'item'),
            maxLines: 1,
            style: AppTextStyle.labelMedium.copyWith(
              color: scheme.onPrimaryContainer,
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  final String label;
  final int count;
  const _MonthHeader({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.space20,
        AppDimens.space20,
        AppDimens.space20,
        AppDimens.space8,
      ),
      child: Row(
        children: [
          Text(
            label,
            style: AppTextStyle.sectionHeader.copyWith(color: scheme.onSurface),
          ),
          const SizedBox(width: AppDimens.space10),
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(AppDimens.radiusPill),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.space8,
                vertical: AppDimens.space4,
              ),
              child: Text(
                Format.count(count, 'item'),
                style: AppTextStyle.labelSmall.copyWith(
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single gallery cell: rounded, cover-cropped, with selection chrome.
///
/// Decoding is capped with `cacheWidth`, so a full-resolution source never
/// lands in the image cache at full size for a 190px tile.
class _PhotoCell extends StatelessWidget {
  final Uint8List? bytes;
  final int decodeWidth;
  final Category category;
  final bool unavailable;
  final String name;
  final String? semanticLabel;
  final String heroTag;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final ValueChanged<Offset> onLongPressStart;
  final VoidCallback onVisible;

  const _PhotoCell({
    super.key,
    required this.bytes,
    required this.decodeWidth,
    required this.category,
    required this.unavailable,
    required this.name,
    required this.semanticLabel,
    required this.heroTag,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPressStart,
    required this.onVisible,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final duration = AppMotion.resolve(context, AppMotion.fast);
    final curve = AppMotion.curveFor(context, AppMotion.standard);
    // The glyph already prints PDF on the document mark; a second badge would
    // only duplicate that label inside the same tile.
    final badge = switch (category) {
      Category.video => 'VIDEO',
      _ => null,
    };
    Widget content;
    if (bytes != null) {
      content = Image.memory(
        bytes!,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        cacheWidth: decodeWidth.clamp(1, 4096).toInt(),
        errorBuilder: (context, _, __) => _placeholder(context),
      );
    } else if (unavailable) {
      content = _placeholder(context);
    } else {
      content = _placeholder(context);
      WidgetsBinding.instance.addPostFrameCallback((_) => onVisible());
    }

    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel ?? 'Photo',
      hint: selecting
          ? 'Activates selection for this photo'
          : 'Opens the photo. Long press and drag to select several.',
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onLongPressStart: (details) =>
              onLongPressStart(details.globalPosition),
          child: InkWell(
            onTap: onTap,
            customBorder: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(
                Radius.circular(AppDimens.radiusExtraSmall),
              ),
            ),
            child: AnimatedContainer(
              duration: duration,
              curve: curve,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppDimens.radiusExtraSmall),
                border: Border.all(
                  color: selected ? scheme.primary : Colors.transparent,
                  width: AppDimens.space1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppDimens.radiusExtraSmall),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Hero(tag: heroTag, child: content),
                    if (badge != null)
                      Positioned(
                        left: AppDimens.space6,
                        bottom: AppDimens.space6,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHigh
                                .withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(
                              AppDimens.radiusSmall,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppDimens.space6,
                              vertical: AppDimens.space2,
                            ),
                            child: Text(
                              badge,
                              style: AppTextStyle.labelSmall.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    AnimatedOpacity(
                      opacity: selected ? 1 : 0,
                      duration: duration,
                      curve: curve,
                      child: const IgnorePointer(child: _SelectedOverlay()),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final type = switch (category) {
      Category.video => 'video/mp4',
      Category.pdf => 'application/pdf',
      _ => 'image/jpeg',
    };
    return ColoredBox(
      color: scheme.surfaceContainerHigh,
      child: Center(
        child: NexaFileGlyph(
          name: name,
          type: type,
          size: AppDimens.iconTile,
        ),
      ),
    );
  }
}

class _BrowseTarget {
  final String path;
  final int depth;

  const _BrowseTarget(this.path, this.depth);
}

class _SelectedOverlay extends StatelessWidget {
  const _SelectedOverlay();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.space6),
        child: Container(
          padding: const EdgeInsets.all(AppDimens.space2),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.check_rounded,
            color: scheme.onPrimaryContainer,
            size: AppDimens.iconSmall,
          ),
        ),
      ),
    );
  }
}
