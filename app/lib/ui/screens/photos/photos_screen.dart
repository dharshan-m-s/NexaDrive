import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/material.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/models/file_entry.dart';
import '../../../core/utils/format.dart';
import '../../../services/api.dart';
import '../../../services/image_pipeline.dart';
import '../../../services/session.dart';
import '../../../services/thumbnail_cache.dart';
import '../../widgets/nexa_components.dart';
import '../files/file_share_sheet.dart';
import 'photo_viewer.dart';

/// How many thumbnails are fetched eagerly after listing loads. The grid
/// fetches the rest lazily as tiles scroll into view.
const int _eagerThumbCount = 24;

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

  /// `path -> index`, so the viewer's placeholder lookup is O(1) per build
  /// instead of a linear scan of the whole library.
  Map<String, int> _indexByPath = const {};

  bool _selecting = false;
  final Set<String> _selected = <String>{};
  int _gridColumns = 3;
  int? _activePointer;
  bool _dragSelecting = false;
  final Map<String, GlobalKey> _cellKeys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _attachDiskCache();
    _loadGridColumns();
    load();
  }

  static const _gridColumnsPreference = 'nexadrive.photos.grid_columns';

  Future<void> _loadGridColumns() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_gridColumnsPreference);
      if (saved != null && mounted) {
        setState(() => _gridColumns = saved.clamp(1, 8).toInt());
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
    var draft = _gridColumns;
    final selected = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Gallery layout'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '$draft columns',
                style: AppTextStyle.headline.copyWith(
                  color: AppColors.labelPrimaryFor(
                    Theme.of(context).brightness,
                  ),
                ),
              ),
              Slider(
                value: draft.toDouble(),
                min: 1,
                max: 8,
                divisions: 7,
                label: '$draft',
                onChanged: (value) =>
                    setDialogState(() => draft = value.round()),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Larger photos'),
                  Text(
                    'More columns',
                    style: AppTextStyle.caption1.copyWith(
                      color: AppColors.labelSecondaryFor(
                        Theme.of(context).brightness,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, draft),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
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
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_dragSelecting || event.pointer != _activePointer) return;
    _selectCellAt(event.position);
  }

  void _onPointerUp(PointerEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    _dragSelecting = false;
  }

  void _beginDragSelection(int index, Offset globalPosition) {
    if (!_selecting) {
      setState(() {
        _selecting = true;
        _selected.add(_pathAt(index));
      });
      widget.onSelectionChanged?.call(true);
    }
    _dragSelecting = true;
    _selectCellAt(globalPosition);
  }

  void _selectCellAt(Offset globalPosition) {
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
    if (hitPath == null || _selected.contains(hitPath)) return;
    setState(() => _selected.add(hitPath!));
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
      final photos = await widget.api.photos();
      if (!mounted) return;
      setState(() {
        _photos = photos;
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

  /// Rebuilds the derived month buckets and the path index.
  void _reindex() {
    _indexByPath = {
      for (var i = 0; i < _photos.length; i++) _pathAt(i): i,
    };
    _groups = _computeGroups();
  }

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
      if (e.status >= 500) return 'The server could not list your photos.';
      return e.message;
    }
    return 'Check your connection and try again.';
  }

  void _open(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoViewer(
          photos: _photos,
          initialIndex: index,
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
    if (_selecting) {
      _toggleSelect(index);
    } else {
      _open(index);
    }
  }

  void _onCellLongPress(int index, Offset globalPosition) {
    _beginDragSelection(index, globalPosition);
  }

  void _toggleSelect(int index) {
    final path = _pathAt(index);
    setState(() {
      if (_selected.contains(path)) {
        _selected.remove(path);
      } else {
        _selected.add(path);
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_photos.isNotEmpty && _selected.length == _photos.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(_photos.map((photo) => (photo['path'] ?? '').toString()));
      }
      _selecting = _selected.isNotEmpty;
    });
    widget.onSelectionChanged?.call(_selecting);
  }

  String _pathAt(int index) => (_photos[index]['path'] ?? '').toString();

  Future<void> _deleteSelected() async {
    final count = _selected.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move to Trash'),
        content: Text(
          count == 1
              ? 'Move 1 photo to trash?'
              : 'Move $count photos to trash?',
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
    final removed = _selected.toList();
    try {
      await widget.api.batch(action: 'delete', paths: removed);
      _exitSelection();
      if (!mounted) return;
      setState(() {
        _photos.removeWhere((p) => removed.contains(p['path']));
        _reindex();
      });
      _toast('${Format.count(removed.length, 'photo')} moved to Trash');
    } catch (e) {
      if (mounted) _toast(e.toString());
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
    final brightness = Theme.of(context).brightness;
    final photoCount = _photos.length;

    return NexaPage(
      title: _selecting ? Format.count(_selected.length, 'photo') : 'Photos',
      bottomSafeArea: false,
      subtitle: _selecting
          ? 'Drag across photos to select · Tap to refine'
          : photoCount == 0
              ? 'All your photos in one place'
              : Format.count(photoCount, 'photo'),
      headerAction: _selecting
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Change grid density',
                  onPressed: _showGridDensityPicker,
                  icon: Icon(
                    Icons.grid_4x4_rounded,
                    color: AppColors.accentTextFor(brightness),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh photos',
                  onPressed: _loading ? null : load,
                  icon: Icon(
                    Icons.refresh_rounded,
                    color: AppColors.accentTextFor(brightness),
                  ),
                ),
              ],
            ),
      body: _body(),
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
        icon: Icons.cloud_off_rounded,
        title: 'Can’t load photos',
        hint: _error,
        actionLabel: 'Retry',
        onAction: load,
      );
    }
    if (_photos.isEmpty) {
      return NexaEmptyState(
        icon: Icons.photo_library_outlined,
        title: 'No photos yet',
        hint: 'Upload photos from My files and they’ll appear here.',
        actionLabel: 'Refresh',
        onAction: load,
      );
    }

    final groups = _groups;
    final bottomClearance =
        _selecting ? AppDimens.space24 : MediaQuery.paddingOf(context).bottom;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final contentWidth = (viewportWidth - AppDimens.pageMargin * 2)
        .clamp(80.0, AppDimens.contentMaxWidth);
    final tileWidth =
        (contentWidth - AppDimens.space4 * (_gridColumns - 1)) / _gridColumns;
    final decodeWidth =
        (tileWidth * MediaQuery.devicePixelRatioOf(context)).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: load,
            child: Listener(
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              onPointerCancel: _onPointerUp,
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
                          horizontal: AppDimens.space4,
                        ),
                        sliver: SliverGrid.builder(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: _gridColumns,
                            mainAxisSpacing: AppDimens.space4,
                            crossAxisSpacing: AppDimens.space4,
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
                              unavailable: _noThumbnail.contains(path),
                              semanticLabel: _photos[index]['name']?.toString(),
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
              MediaQuery.viewPaddingOf(context).bottom + AppDimens.space10,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: NexaLiquidGlass(
                  borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                  blurSigma: 2,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.space6,
                    vertical: AppDimens.space4,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Cancel selection',
                        onPressed: _exitSelection,
                        icon: const Icon(Icons.close_rounded),
                      ),
                      Expanded(
                        child: Text(
                          Format.count(_selected.length, 'photo'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.bodyEmphasized.copyWith(
                            color: AppColors.labelPrimaryFor(
                              Theme.of(context).brightness,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: _selected.length == _photos.length
                            ? 'Clear selection'
                            : 'Select all',
                        onPressed: _toggleSelectAll,
                        icon: Icon(
                          _selected.length == _photos.length
                              ? Icons.deselect_rounded
                              : Icons.select_all_rounded,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Share selected photos',
                        onPressed: _selected.isEmpty ? null : _shareSelected,
                        icon: const Icon(Icons.share_outlined),
                      ),
                      IconButton(
                        tooltip: 'Move selected photos to Trash',
                        onPressed: _selected.isEmpty ? null : _deleteSelected,
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: AppColors.errorFor(
                            Theme.of(context).brightness,
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
      ],
    );
  }

  Uint8List? _thumbBytes(int index) {
    if (_noThumbnail.contains(_pathAt(index))) return null;
    return _images.peekThumbnail(_thumbKey(index));
  }
}

class _MonthHeader extends StatelessWidget {
  final String label;
  final int count;
  const _MonthHeader({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
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
            style: AppTextStyle.sectionHeader.copyWith(
              color: AppColors.textPrimaryFor(brightness),
            ),
          ),
          const SizedBox(width: AppDimens.space10),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surfaceAltFor(brightness),
              borderRadius: BorderRadius.circular(AppDimens.radiusPill),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.space8,
                vertical: AppDimens.space4,
              ),
              child: Text(
                Format.count(count, 'photo'),
                style: AppTextStyle.caption.copyWith(
                  color: AppColors.textSecondaryFor(brightness),
                  fontWeight: FontWeight.w600,
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
  final bool unavailable;
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
    required this.unavailable,
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
    final brightness = Theme.of(context).brightness;
    final onAccent = AppColors.onAccentContainerFor(brightness);

    Widget content;
    if (bytes != null) {
      content = Image.memory(
        bytes!,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        cacheWidth: decodeWidth.clamp(1, 4096).toInt(),
        errorBuilder: (context, _, __) => _placeholder(brightness),
      );
    } else if (unavailable) {
      content = _placeholder(
        brightness,
        icon: Icons.image_not_supported_outlined,
      );
    } else {
      content = _placeholder(brightness);
      WidgetsBinding.instance.addPostFrameCallback((_) => onVisible());
    }

    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel ?? 'Photo',
      hint: selecting
          ? 'Activates selection for this photo'
          : 'Opens the photo. Long press and drag to select several.',
      child: GestureDetector(
        onTap: onTap,
        onLongPressStart: (details) => onLongPressStart(details.globalPosition),
        child: AnimatedScale(
          scale: selected ? 0.965 : 1,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppDimens.radiusInner),
              border: Border.all(
                color: selected
                    ? AppColors.accentFor(brightness)
                    : Colors.transparent,
                width: 2.5,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppDimens.radiusInner),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(tag: heroTag, child: content),
                  AnimatedOpacity(
                    opacity: selected ? 1 : 0,
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    child: IgnorePointer(
                      child: _SelectedOverlay(onAccent: onAccent),
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

  Widget _placeholder(Brightness brightness,
      {IconData icon = Icons.photo_outlined}) {
    return Container(
      color: brightness == Brightness.dark
          ? AppColors.surfaceAltDark
          : AppColors.surfaceAltLight,
      child: Center(
        child: Icon(
          icon,
          color: AppColors.textTertiaryFor(brightness),
          size: AppDimens.iconMedium,
        ),
      ),
    );
  }
}

class _SelectedOverlay extends StatelessWidget {
  final Color onAccent;
  const _SelectedOverlay({required this.onAccent});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppDimens.radiusInner),
        border: Border.all(color: AppColors.accentFor(brightness), width: 2.5),
        color: AppColors.accentFor(brightness).withValues(alpha: 0.28),
      ),
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.space6),
          child: Icon(Icons.check_circle_rounded, color: onAccent, size: 22),
        ),
      ),
    );
  }
}
