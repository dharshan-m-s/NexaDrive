import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_motion.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/models/file_entry.dart';
import '../../../services/api.dart';
import '../../../services/download_service.dart';
import '../../../services/image_pipeline.dart';
import '../files/file_share_sheet.dart';
import '../../widgets/one_ui_sheet.dart';

/// Full-resolution photo viewer.
///
/// ## IMAGE QUALITY CONTRACT
/// (regression-tested in `test/image_pipeline_test.dart`)
///
/// 1. Every displayed frame comes from [ImageRepository.original] — the
///    ORIGINAL bytes served by `/api/files/download`. The thumbnail endpoint is
///    only ever called through [ImageRepository.thumbnail], never here.
/// 2. Original and thumbnail requests use disjoint cache keys
///    ([ImageRendition] is part of [ImageKey]), so a thumbnail can never be
///    substituted for an original.
/// 3. Decoding happens with `ui.instantiateImageCodec(widget.bytes)` at the
///    image's natural size — no target width/height — so every original pixel
///    is decoded.
/// 4. The thumbnail is used ONLY as a low-cost placeholder behind the loading
///    indicator, and is visually dimmed so it can never be mistaken for the
///    final image. It is fetched from the separate thumbnail key space.
/// 5. Zoom/pan transform the decoded full-resolution image directly; the fit
///    scale is computed from the real pixel dimensions, so zooming in reveals
///    genuine texture instead of an upscaled preview.
class PhotoViewer extends StatefulWidget {
  final List<Map<String, dynamic>> photos;
  final int initialIndex;
  final Api api;

  /// Shared image pipeline. Callers pass their screen's repository so grids
  /// and the viewer reuse one bounded cache.
  final ImageRepository images;

  /// Optional low-res preview for a page, shown while the original downloads.
  /// Grid thumbnails flow in here; originals never do.
  final Uint8List? Function(String path)? thumbnailLookup;

  /// Called after a photo is moved to Trash so the grid can refresh.
  final ValueChanged<String>? onDeleted;

  const PhotoViewer({
    super.key,
    required this.photos,
    required this.initialIndex,
    required this.api,
    required this.images,
    this.thumbnailLookup,
    this.onDeleted,
  });

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late PageController _controller;
  late List<Map<String, dynamic>> _photos;
  late int _current;

  /// Decoded ORIGINAL frames for the visible neighbourhood. Bounded: the
  /// current page plus one neighbour on each side, each disposed on eviction.
  final Map<String, ui.Image> _decoded = {};
  final Set<String> _inFlight = {};
  final Map<String, String> _errors = {};

  /// How many pages either side of the current one stay decoded.
  static const _decodeWindow = 1;

  late final DownloadService _downloads = DownloadService(widget.api);

  @override
  void initState() {
    super.initState();
    _photos = List<Map<String, dynamic>>.of(widget.photos);
    _current = widget.initialIndex.clamp(0, math.max(0, _photos.length - 1));
    _controller = PageController(initialPage: _current);
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefetchAround(_current));
  }

  @override
  void dispose() {
    _controller.dispose();
    for (final image in _decoded.values) {
      image.dispose();
    }
    _decoded.clear();
    super.dispose();
  }

  String _pathAt(int index) => (_photos[index]['path'] ?? '').toString();

  ImageKey _originalKey(int index) => ImageRepository.keyFor(
        _photos[index],
        namespace: widget.api.session.cacheNamespace,
        rendition: ImageRendition.original,
      );

  /// Loads + decodes originals for the pages around [index], and releases the
  /// frames that fell outside the window.
  void _prefetchAround(int index) {
    for (var i = index - _decodeWindow; i <= index + _decodeWindow; i++) {
      if (i >= 0 && i < _photos.length) {
        _ensureDecoded(i);
      }
    }
    _evictOutsideWindow(index);
  }

  void _evictOutsideWindow(int index) {
    final keep = <String>{
      for (var i = index - _decodeWindow; i <= index + _decodeWindow; i++)
        if (i >= 0 && i < _photos.length) _pathAt(i),
    };
    final stale = _decoded.keys.where((p) => !keep.contains(p)).toList();
    for (final path in stale) {
      _decoded.remove(path)?.dispose();
    }
    if (stale.isNotEmpty && mounted) setState(() {});
  }

  Future<void> _ensureDecoded(int index) async {
    if (index < 0 || index >= _photos.length) return;
    final path = _pathAt(index);
    if (_decoded.containsKey(path) || _inFlight.contains(path)) return;
    _inFlight.add(path);
    final key = _originalKey(index);
    try {
      // ORIGINAL bytes — never the thumbnail endpoint, never the thumbnail
      // cache. This is the single line that guarantees viewer sharpness.
      final data = await widget.images.original(key);
      final image = await _decode(data.bytes);
      if (!mounted) {
        image?.dispose();
        return;
      }
      setState(() {
        _errors.remove(path);
        if (image != null) _decoded[path] = image;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _errors[path] = _friendly(e));
      }
    } finally {
      _inFlight.remove(path);
    }
  }

  /// Decodes at natural size: no `targetWidth`/`targetHeight`, so the engine
  /// produces every original pixel. Any resize here is the classic cause of a
  /// blurry viewer.
  Future<ui.Image?> _decode(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  void _retry(int index) {
    final path = _pathAt(index);
    widget.images.clearFailure(_originalKey(index));
    setState(() => _errors.remove(path));
    _ensureDecoded(index);
  }

  String _friendly(Object e) {
    if (e is ApiException) {
      if (e.status == 404) return 'This photo is no longer on the server.';
      if (e.status == 401) return 'Your session expired. Sign in again.';
      return e.message;
    }
    return 'The original photo could not be downloaded. Check your connection.';
  }

  void _onPageChanged(int index) {
    setState(() => _current = index);
    _prefetchAround(index);
  }

  Future<void> _goTo(int index) async {
    if (index < 0 || index >= _photos.length) return;
    await _controller.animateToPage(
      index,
      duration: AppMotion.resolve(context, AppMotion.fast),
      curve: AppMotion.curveFor(context, AppMotion.enter),
    );
  }

  Future<void> _downloadCurrent() async {
    final p = _photos[_current];
    final name = p['name'] as String? ?? _pathAt(_current).split('/').last;
    try {
      final result = await _downloads.saveAs(
        remotePath: _pathAt(_current),
        fileName: name,
      );
      if (!mounted) return;
      if (result == null) {
        _toast('Download cancelled');
      } else {
        _toast('Saved to ${result.location}');
      }
    } catch (e) {
      if (mounted) _toast(e.toString());
    }
  }

  void _shareCurrent() {
    final p = _photos[_current];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FileShareSheet(
        api: widget.api,
        files: [FileEntry.fromJson(Map<String, dynamic>.from(p))],
      ),
    );
  }

  Future<void> _deleteCurrent() async {
    final index = _current;
    final name = _photos[index]['name']?.toString() ?? _pathAt(index).split('/').last;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move to Trash'),
        content: Text('Move "$name" to trash?'),
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
    if (confirmed != true) return;
    try {
      await widget.api.batch(action: 'delete', paths: [_pathAt(index)]);
    } catch (e) {
      if (mounted) _toast(e.toString());
      return;
    }
    final removed = _pathAt(index);
    widget.onDeleted?.call(removed);
    if (!mounted) return;
    if (_photos.length == 1) {
      Navigator.of(context).pop();
      return;
    }
    _decoded.remove(removed)?.dispose();
    setState(() {
      _photos.removeAt(index);
      _errors.remove(removed);
      _current = index.clamp(0, _photos.length - 1);
    });
    _toast('Moved to Trash');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_controller.hasClients) _controller.jumpToPage(_current);
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showActions() {
    showOneUiSheet<void>(
      context,
      builder: (sheetContext) => OneUiSheetBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OneUiSheetHeader(
              title: _photos[_current]['name']?.toString() ?? 'Photo',
              subtitle: '${_current + 1} of ${_photos.length}',
            ),
            OneUiSheetAction(
              icon: Icons.download_outlined,
              title: 'Save to device',
              onTap: () {
                Navigator.pop(sheetContext);
                _downloadCurrent();
              },
            ),
            OneUiSheetAction(
              icon: Icons.share_outlined,
              title: 'Share',
              onTap: () {
                Navigator.pop(sheetContext);
                _shareCurrent();
              },
            ),
            OneUiSheetAction(
              icon: Icons.delete_outline_rounded,
              title: 'Move to Trash',
              destructive: true,
              onTap: () {
                Navigator.pop(sheetContext);
                _deleteCurrent();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.72),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          '${_current + 1} of ${_photos.length}',
          style: AppTextStyle.rowTitle.copyWith(color: Colors.white),
        ),
        actions: [
          IconButton(
            tooltip: 'Photo options',
            onPressed: _showActions,
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: PageView.builder(
              controller: _controller,
              onPageChanged: _onPageChanged,
              itemCount: _photos.length,
              itemBuilder: (context, i) {
                final path = _pathAt(i);
                final error = _errors[path];
                if (error != null) {
                  return _ViewerError(
                    message: error,
                    onRetry: () => _retry(i),
                  );
                }
                final image = _decoded[path];
                if (image == null) {
                  return _LoadingPage(
                    thumbnail: widget.thumbnailLookup?.call(path),
                  );
                }
                return _ZoomablePhoto(
                  key: ValueKey('original:$path'),
                  image: image,
                );
              },
            ),
          ),
          _BottomBar(
            index: _current,
            total: _photos.length,
            onPrevious: _current > 0 ? () => _goTo(_current - 1) : null,
            onNext: _current < _photos.length - 1
                ? () => _goTo(_current + 1)
                : null,
            onDownload: _downloadCurrent,
            onShare: _shareCurrent,
            onDelete: _deleteCurrent,
          ),
        ],
      ),
    );
  }
}

/// Placeholder shown while the ORIGINAL downloads. The grid thumbnail is
/// heavily dimmed behind the spinner so it can never be mistaken for the
/// final image.
class _LoadingPage extends StatelessWidget {
  final Uint8List? thumbnail;
  const _LoadingPage({this.thumbnail});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (thumbnail != null)
            Positioned.fill(
              child: Opacity(
                opacity: 0.28,
                child: Image.memory(
                  thumbnail!,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                  // Thumbnails are ~512px; never decode them larger.
                  cacheWidth: 1024,
                ),
              ),
            ),
          const CircularProgressIndicator(color: Colors.white70, strokeWidth: 2),
        ],
      ),
    );
  }
}

/// Graceful failure with a clear cause and a retry affordance.
class _ViewerError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ViewerError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.space32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 44),
            const SizedBox(height: AppDimens.space16),
            Text(
              'Can\u2019t open this photo',
              textAlign: TextAlign.center,
              style: AppTextStyle.sectionHeader.copyWith(color: Colors.white),
            ),
            const SizedBox(height: AppDimens.space8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyle.rowSubtitle.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: AppDimens.space20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: AppDimens.iconSmall),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int index;
  final int total;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onDownload;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  const _BottomBar({
    required this.index,
    required this.total,
    required this.onPrevious,
    required this.onNext,
    required this.onDownload,
    required this.onShare,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        color: Colors.black.withValues(alpha: 0.72),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppDimens.space4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  tooltip: 'Previous photo',
                  onPressed: onPrevious,
                  color: Colors.white,
                  disabledColor: Colors.white24,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                IconButton(
                  tooltip: 'Save to device',
                  onPressed: onDownload,
                  color: Colors.white,
                  icon: const Icon(Icons.download_outlined),
                ),
                IconButton(
                  tooltip: 'Share',
                  onPressed: onShare,
                  color: Colors.white,
                  icon: const Icon(Icons.share_outlined),
                ),
                IconButton(
                  tooltip: 'Move to Trash',
                  onPressed: onDelete,
                  color: Colors.white,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
                IconButton(
                  tooltip: 'Next photo',
                  onPressed: onNext,
                  color: Colors.white,
                  disabledColor: Colors.white24,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pans/zooms a photo while keeping its original pixels on screen.
///
/// The decoded [RawImage] lays out at *native* resolution and the
/// [InteractiveViewer]'s own transform provides the initial "fit" scale, so
/// pinching in reveals real texture instead of a re-scaled preview.
class _ZoomablePhoto extends StatefulWidget {
  final ui.Image image;
  const _ZoomablePhoto({super.key, required this.image});

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto>
    with SingleTickerProviderStateMixin {
  final TransformationController _transform = TransformationController();
  Size? _viewport;
  double _fit = 1;
  bool _fitted = false;

  late final AnimationController _zoomAnim;
  Matrix4Tween? _zoomTween;

  @override
  void initState() {
    super.initState();
    _zoomAnim = AnimationController(
      vsync: this,
      duration: AppMotion.fast,
    );
    _zoomAnim.addListener(() {
      final tween = _zoomTween;
      if (tween != null) _transform.value = tween.transform(_zoomAnim.value);
    });
    _zoomAnim.addStatusListener((status) {
      if (status == AnimationStatus.completed) _zoomTween = null;
    });
  }

  @override
  void didUpdateWidget(covariant _ZoomablePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) {
      _fitted = false;
      _transform.value = Matrix4.identity();
    }
  }

  @override
  void dispose() {
    _zoomAnim.dispose();
    _transform.dispose();
    super.dispose();
  }

  Size get _photo =>
      Size(widget.image.width.toDouble(), widget.image.height.toDouble());

  double _fitFor(Size viewport, Size photo) {
    if (photo.width <= 0 || photo.height <= 0) return 1;
    return math.min(viewport.width / photo.width, viewport.height / photo.height)
        .clamp(0.02, 4.0);
  }

  /// Maps the image centre onto the viewport centre at [scale].
  Matrix4 _matrixFor(double scale, Size viewport, Size photo) {
    return Matrix4.identity()
      ..translateByDouble(viewport.width / 2, viewport.height / 2, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-photo.width / 2, -photo.height / 2, 0, 1);
  }

  void _applyFit() {
    final vp = _viewport;
    if (vp == null || _fitted) return;
    _transform.value = _matrixFor(_fit, vp, _photo);
    _fitted = true;
  }

  void _toggleZoom() {
    final vp = _viewport;
    if (vp == null) return;
    final nowScale = _transform.value.getMaxScaleOnAxis();
    final target = nowScale > _fit * 1.25 ? _fit : _fit * 3.0;
    final end = _matrixFor(target, vp, _photo);
    _zoomTween = Matrix4Tween(begin: _transform.value.clone(), end: end);
    _zoomAnim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        _viewport = viewport;
        final photo = _photo;
        final fit = _fitFor(viewport, photo);
        if ((_fit - fit).abs() > 0.0001) {
          _fit = fit;
          _fitted = false;
        }
        if (!_fitted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(_applyFit);
          });
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: _toggleZoom,
          child: InteractiveViewer(
            transformationController: _transform,
            constrained: false,
            minScale: math.max(_fit * 0.9, 0.5),
            maxScale: math.max(_fit * 8, 1.4),
            clipBehavior: Clip.none,
            child: RawImage(
              image: widget.image,
              fit: BoxFit.none,
              filterQuality: FilterQuality.high,
              isAntiAlias: true,
            ),
          ),
        );
      },
    );
  }
}
