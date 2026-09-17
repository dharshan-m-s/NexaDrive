import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../core/models/file_entry.dart';
import '../../../services/api.dart';
import '../files/file_share_sheet.dart';

class PhotoViewer extends StatefulWidget {
  final List<Map<String, dynamic>> photos;
  final int initialIndex;
  final Api api;
  const PhotoViewer({
    super.key,
    required this.photos,
    required this.initialIndex,
    required this.api,
  });

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late PageController _controller;
  late int _current;
  final Map<String, Uint8List> _fullCache = {};

  // Paging through a big library must not accumulate every original in RAM.
  // Hold at most a few full-resolution images (current page + near neighbors).
  static const _maxCached = 5;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
    _ensureCached(widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    _fullCache.clear();
    super.dispose();
  }

  void _cacheInsert(String path, Uint8List bytes) {
    _fullCache[path] = bytes;
    if (_fullCache.length <= _maxCached) return;
    // Evict the cached entry furthest from the current page.
    String? evict;
    var furthest = -1;
    for (final entry in _fullCache.entries) {
      final idx = widget.photos.indexWhere((p) => p['path'] == entry.key);
      if (idx == -1) continue;
      final dist = (idx - _current).abs();
      if (dist > furthest) {
        furthest = dist;
        evict = entry.key;
      }
    }
    if (evict != null) _fullCache.remove(evict);
  }

  Future<void> _ensureCached(int index) async {
    if (index < 0 || index >= widget.photos.length) return;
    final path = widget.photos[index]['path'] as String;
    if (_fullCache.containsKey(path)) return;
    try {
      final bytes = await widget.api.download(path);
      if (mounted) setState(() => _cacheInsert(path, bytes));
    } catch (_) {}
  }

  void _onPageChanged(int index) {
    setState(() => _current = index);
    for (final offset in [-1, 0, 1]) {
      _ensureCached(index + offset);
    }
  }

  Future<void> _downloadCurrent() async {
    try {
      final p = widget.photos[_current];
      final name = p['name'] as String? ?? (p['path'] as String).split('/').last;
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Save $name',
        fileName: name,
        bytes: Uint8List(0),
      );
      final outPath = uri?.toFilePath();
      if (outPath == null) return;
      await widget.api.downloadToFile(p['path'] as String, outPath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved to $outPath')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  void _shareCurrent() {
    final p = widget.photos[_current];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FileShareSheet(
        api: widget.api,
        files: [FileEntry.fromJson(Map<String, dynamic>.from(p))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('${_current + 1} of ${widget.photos.length}'),
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            onPageChanged: _onPageChanged,
            itemCount: widget.photos.length,
            itemBuilder: (context, i) {
              final p = widget.photos[i];
              final bytes = _fullCache[p['path']];
              if (bytes == null) {
                _ensureCached(i);
                return const Center(
                  child: CircularProgressIndicator(
                    color: Colors.white54,
                    strokeWidth: 2,
                  ),
                );
              }
              return _ZoomablePhoto(bytes: bytes);
            },
          ),
          // Bottom bar (translucent — One UI photo viewer keeps controls low).
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                color: Colors.white.withValues(alpha: 0.06),
                child: SafeArea(
                  top: false,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        tooltip: 'Download',
                        icon: const Icon(Icons.download_outlined, color: Colors.white),
                        onPressed: _downloadCurrent,
                      ),
                      IconButton(
                        tooltip: 'Share',
                        icon: const Icon(Icons.share_outlined, color: Colors.white),
                        onPressed: _shareCurrent,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pans/zooms a photo while keeping its original pixels on screen.
///
/// The decoded [RawImage] lays out at *native* resolution and the
/// [InteractiveViewer]'s own transform provides the initial "fit" scale, so
/// pinching in reveals real texture instead of a re-scaled preview. The
/// classic `FittedBox`-in-viewer approach collapses the image to screen size
/// in the layer tree; here the transform is the only scale applied, which
/// keeps 1:1 clarity all the way up.
class _ZoomablePhoto extends StatefulWidget {
  final Uint8List bytes;
  const _ZoomablePhoto({required this.bytes});

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto>
    with SingleTickerProviderStateMixin {
  final TransformationController _transform = TransformationController();
  ui.Image? _image;
  Size? _viewport;
  double _fit = 1;
  bool _fitted = false;
  double? _pendingFit;

  late final AnimationController _zoomAnim;
  Matrix4Tween? _zoomTween;

  @override
  void initState() {
    super.initState();
    _decode();
    _zoomAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
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
  void dispose() {
    _zoomAnim.dispose();
    _transform.dispose();
    _image?.dispose();
    super.dispose();
  }

  Future<void> _decode() async {
    ui.Image? decoded;
    try {
      final codec = await ui.instantiateImageCodec(widget.bytes);
      final frame = await codec.getNextFrame();
      decoded = frame.image;
      codec.dispose();
    } catch (_) {
      return;
    }
    if (!mounted) {
      decoded.dispose();
      return;
    }
    setState(() => _image = decoded);
  }

  double _fitFor(Size viewport, Size photo) {
    if (photo.width <= 0 || photo.height <= 0) return 1;
    return math.min(
          viewport.width / photo.width,
          viewport.height / photo.height,
        )
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
    final img = _image;
    final vp = _viewport;
    final fit = _pendingFit;
    if (img == null || vp == null || fit == null) return;
    // Never stomp an in-flight pinch or double-tap animation.
    if (_fitted && !_zoomAnim.isAnimating) return;
    _transform.value = _matrixFor(fit, vp, Size(img.width.toDouble(), img.height.toDouble()));
    _fitted = true;
  }

  void _toggleZoom() {
    final vp = _viewport;
    final img = _image;
    if (vp == null || img == null) return;
    final nowScale = _transform.value.getMaxScaleOnAxis();
    final target = nowScale > _fit * 1.25 ? _fit : _fit * 3.0;
    final end = _matrixFor(
      target,
      vp,
      Size(img.width.toDouble(), img.height.toDouble()),
    );
    _zoomTween = Matrix4Tween(begin: _transform.value.clone(), end: end);
    _zoomAnim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        _viewport = viewport;
        final img = _image;
        if (img == null) {
          return const Center(
            child: CircularProgressIndicator(
              color: Colors.white54,
              strokeWidth: 2,
            ),
          );
        }
        final photo = Size(img.width.toDouble(), img.height.toDouble());
        final fit = _fitFor(viewport, photo);
        if ((_fit - fit).abs() > 0.0001) {
          _fit = fit;
          _pendingFit = fit;
          WidgetsBinding.instance.addPostFrameCallback((_) => _applyFit());
        } else if (!_fitted) {
          _pendingFit ??= fit;
          WidgetsBinding.instance.addPostFrameCallback((_) => _applyFit());
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
              image: img,
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