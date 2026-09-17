import 'dart:typed_data';

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
import '../../widgets/one_ui_action_bar.dart';
import '../../widgets/one_ui_empty_state.dart';
import '../../widgets/one_ui_page.dart';
import '../files/file_share_sheet.dart';
import 'photo_viewer.dart';

/// Grid tile edge in logical pixels. Kept here so the decode size and the
/// layout size can never drift apart.
const double _tileExtent = 190;

/// How many thumbnails are fetched eagerly after listing loads. The grid
/// fetches the rest lazily as tiles scroll into view.
const int _eagerThumbCount = 24;

class PhotosScreen extends StatefulWidget {
  final Api api;
  final Session session;
  const PhotosScreen({super.key, required this.api, required this.session});

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

  bool _selecting = false;
  final Set<String> _selected = <String>{};

  @override
  void initState() {
    super.initState();
    _attachDiskCache();
    load();
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
          thumbnailLookup: (path) {
            final i = _photos.indexWhere((p) => p['path'] == path);
            if (i < 0) return null;
            return _images.peekThumbnail(_thumbKey(i));
          },
          onDeleted: (path) {
            if (!mounted) return;
            setState(() => _photos.removeWhere((p) => p['path'] == path));
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

  void _onCellLongPress(int index) {
    if (!_selecting) {
      setState(() {
        _selecting = true;
        _selected.add(_pathAt(index));
      });
    }
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

  String _pathAt(int index) => (_photos[index]['path'] ?? '').toString();

  Future<void> _deleteSelected() async {
    final count = _selected.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move to Trash'),
        content: Text(
          count == 1 ? 'Move 1 photo to trash?' : 'Move $count photos to trash?',
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
      setState(() => _photos.removeWhere((p) => removed.contains(p['path'])));
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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FileShareSheet(api: widget.api, files: entries),
    );
    if (mounted) _exitSelection();
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // -------------------------------------------------------------- grouping
  /// Photos newest-first, grouped into month buckets.
  List<(String, List<int>)> get _groups {
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
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[t.month - 1]} ${t.year}';
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final photoCount = _photos.length;

    return OneUiPage(
      title: _selecting ? Format.count(_selected.length, 'photo') : 'Photos',
      subtitle: _selecting
          ? 'Tap photos to include or exclude'
          : photoCount == 0
              ? 'All your photos in one place'
              : Format.count(photoCount, 'photo'),
      headerAction: _selecting
          ? IconButton(
              tooltip: 'Cancel selection',
              onPressed: _exitSelection,
              icon: const Icon(Icons.close_rounded),
            )
          : IconButton(
              tooltip: 'Refresh photos',
              onPressed: load,
              icon: Icon(Icons.refresh_rounded, color: AppColors.accentFor(brightness)),
            ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return OneUiEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Can\u2019t load photos',
        hint: _error,
        actionLabel: 'Retry',
        onAction: load,
      );
    }
    if (_photos.isEmpty) {
      return OneUiEmptyState(
        icon: Icons.photo_library_outlined,
        title: 'No photos yet',
        hint: 'Upload photos from My files and they\u2019ll appear here.',
        actionLabel: 'Refresh',
        onAction: load,
      );
    }

    final groups = _groups;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: load,
            child: CustomScrollView(
              slivers: [
                for (final (label, indices) in groups) ...[
                  SliverToBoxAdapter(
                    child: _MonthHeader(label: label, count: indices.length),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.space4,
                    ),
                    sliver: SliverGrid.builder(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: _tileExtent,
                        mainAxisSpacing: AppDimens.space4,
                        crossAxisSpacing: AppDimens.space4,
                      ),
                      itemCount: indices.length,
                      itemBuilder: (context, i) {
                        final index = indices[i];
                        return _PhotoCell(
                          bytes: _thumbBytes(index),
                          unavailable: _noThumbnail.contains(_pathAt(index)),
                          semanticLabel: _photos[index]['name']?.toString(),
                          selected: _selected.contains(_pathAt(index)),
                          onTap: () => _onCellTap(index),
                          onLongPress: () => _onCellLongPress(index),
                          onVisible: () => _ensureThumb(_images, index),
                        );
                      },
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: AppDimens.space16),
                  ),
                ],
                const SliverToBoxAdapter(
                  child: SizedBox(height: AppDimens.space24),
                ),
              ],
            ),
          ),
        ),
        if (_selecting)
          OneUiActionBar(
            leading: IconButton(
              tooltip: 'Cancel selection',
              onPressed: _exitSelection,
              icon: const Icon(Icons.close_rounded),
            ),
            title: Format.count(_selected.length, 'photo'),
            actions: [
              OneUiActionItem(
                icon: Icons.share_outlined,
                label: 'Share',
                onTap: _shareSelected,
              ),
              OneUiActionItem(
                icon: Icons.delete_outline_rounded,
                label: 'Trash',
                color: AppColors.errorFor(Theme.of(context).brightness),
                onTap: _deleteSelected,
              ),
            ],
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
          const SizedBox(width: AppDimens.space8),
          Text(
            Format.count(count, 'photo'),
            style: AppTextStyle.caption.copyWith(
              color: AppColors.textSecondaryFor(brightness),
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
  final bool unavailable;
  final String? semanticLabel;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onVisible;

  const _PhotoCell({
    required this.bytes,
    required this.unavailable,
    required this.semanticLabel,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onVisible,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final onAccent = AppColors.onAccentContainerFor(brightness);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final decodeWidth = (_tileExtent * dpr).round();

    Widget content;
    if (bytes != null) {
      content = Image.memory(
        bytes!,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        cacheWidth: decodeWidth,
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
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppDimens.radiusInner),
              child: content,
            ),
            if (selected) _SelectedOverlay(onAccent: onAccent),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(Brightness brightness, {IconData icon = Icons.photo_outlined}) {
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
