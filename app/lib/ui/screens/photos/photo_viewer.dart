import 'dart:async';
import 'dart:math' as math;
import '../../widgets/nexa_components.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_motion.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/models/file_entry.dart';
import '../../../core/utils/format.dart';
import '../../../services/api.dart';
import '../../../services/download_service.dart';
import '../../../services/image_decode_policy.dart';
import '../../../services/image_decoder.dart';
import '../../../services/image_pipeline.dart';
import '../files/file_share_sheet.dart';

/// Full-screen photo viewer.
///
/// ## Image quality and memory contract
/// (regression-tested in `test/image_pipeline_test.dart` and
/// `test/image_decode_policy_test.dart`)
///
/// 1. The viewer displays a bounded server preview (longest edge
///    [_previewMaxEdge]) rather than downloading the full original into
///    memory. A 12 MP photo is not held as a 48 MB RGBA frame just to fill a
///    phone screen.
/// 2. Preview and grid-thumbnail requests use disjoint cache keys
///    ([ImageRendition] plus `maxEdge` is part of [ImageKey]), so warming the
///    grid can never substitute its 512 px thumbnail for the viewer image.
/// 3. For formats the server cannot preview (HEIC/AVIF without a codec), the
///    viewer falls back to [ImageRepository.original] and never shows a
///    blurry grid thumbnail in place of the photo.
/// 4. Decoding goes through [ImageDecoder]. The preview is already bounded;
///    a fallback original uses the natural/bounded policy.
/// 5. Filter quality follows the current scale: mipmapped while minifying and
///    bicubic once the image is at or above 1:1.
/// 6. A failure is reported with a retry action. It is never swallowed,
///    because a swallowed failure leaves the viewer sitting on the loading
///    placeholder.
/// 7. The grid thumbnail is used ONLY as a blurred, dimmed ambient backdrop
///    behind the loading indicator.
class PhotoViewer extends StatefulWidget {
  final List<Map<String, dynamic>> photos;
  final int initialIndex;
  final Api api;

  /// Shared image pipeline. Callers pass their screen's repository so grids
  /// and the viewer reuse one bounded cache.
  final ImageRepository images;

  /// Optional low-res placeholder for a page, shown while the viewer preview
  /// downloads. Grid thumbnails flow in here; viewer previews never do.
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
  static const _decoder = ImageDecoder();

  /// How many pages either side of the current one may stay decoded.
  static const _decodeWindow = 1;

  /// Longest edge requested for the displayed rendition. Large enough to stay
  /// sharp on a phone or laptop, small enough that a square image is ~16 MB
  /// of RGBA instead of the original's 48 MB (or more).
  static const int _previewMaxEdge = 2048;

  late PageController _controller;
  late List<Map<String, dynamic>> _photos;
  late int _current;

  /// Decoded preview frames. The visible page always stays; speculative
  /// neighbours are dropped once the pixel budget is reached.
  final Map<String, ui.Image> _decoded = {};
  final Set<String> _inFlight = {};
  final Map<String, String> _errors = {};

  late final DownloadService _downloads = DownloadService(widget.api);

  /// Mirrors Google Photos' tap-to-reveal chrome: one tap hides both bars, one
  /// tap anywhere brings them back.
  bool _chromeVisible = true;
  Timer? _chromeHideTimer;
  bool _zoomed = false;

  /// Google Photos keeps the photo itself unobstructed. The filmstrip is an
  /// optional browse layer, opened from the overflow instead of a permanent
  /// band of thumbnails at the bottom of every photo.
  bool _filmstripVisible = false;

  /// Bumped when the zoom button is pressed; the active page listens for it.
  final ValueNotifier<int> _zoomSignal = ValueNotifier<int>(0);

  /// Live zoom multiplier relative to "fit", used only by the transient chip.
  final ValueNotifier<double> _zoomLevel = ValueNotifier<double>(1);

  /// The zoom chip appears on a zoom change, then fades on its own timer.
  bool _zoomHintVisible = false;
  Timer? _zoomHintTimer;

  @override
  void initState() {
    super.initState();
    _photos = List<Map<String, dynamic>>.of(widget.photos);
    _current = widget.initialIndex.clamp(0, math.max(0, _photos.length - 1));
    _controller = PageController(initialPage: _current);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _prefetchAround(_current);
        _scheduleChromeHide();
      }
    });
  }

  @override
  void dispose() {
    _chromeHideTimer?.cancel();
    _zoomHintTimer?.cancel();
    _zoomSignal.dispose();
    _zoomLevel.dispose();
    _controller.dispose();
    for (final image in _decoded.values) {
      image.dispose();
    }
    _decoded.clear();
    super.dispose();
  }

  String _pathAt(int index) => (_photos[index]['path'] ?? '').toString();

  ImageKey _previewKey(int index) => ImageRepository.keyFor(
        _photos[index],
        namespace: widget.api.session.cacheNamespace,
        rendition: ImageRendition.thumbnail,
        maxEdge: _previewMaxEdge,
      );

  /// Full original, only used when the server cannot generate a preview.
  ImageKey _originalKey(int index) => ImageRepository.keyFor(
        _photos[index],
        namespace: widget.api.session.cacheNamespace,
        rendition: ImageRendition.original,
      );

  /// Loads the visible page, warms the byte cache for its neighbours, and
  /// releases frames that no longer belong to the window.
  void _prefetchAround(int index) {
    _ensureDecoded(index);
    for (final offset in const [-1, 1]) {
      final neighbour = index + offset;
      if (neighbour < 0 || neighbour >= _photos.length) continue;
      // Warm the bytes (bounded) without necessarily holding the pixels.
      _warmBytes(neighbour);
      _ensureDecoded(neighbour, speculative: true);
    }
    _evictOutsideWindow(index);
    _enforcePixelBudget(index);
  }

  void _warmBytes(int index) {
    if (index < 0 || index >= _photos.length) return;
    final key = _previewKey(index);
    if (widget.images.peekThumbnail(key) != null) return;
    widget.images
        .thumbnail(key, max: _previewMaxEdge)
        .catchError((Object _) => ImageData(Uint8List(0), key: key));
  }

  /// Loads the displayed bytes: a bounded preview, or the original when the
  /// server cannot make one for this format.
  Future<ImageData> _viewerBytes(int index) async {
    try {
      return await widget.images.thumbnail(
        _previewKey(index),
        max: _previewMaxEdge,
      );
    } on ThumbnailUnavailable {
      return widget.images.original(_originalKey(index));
    }
  }

  Future<void> _ensureDecoded(int index, {bool speculative = false}) async {
    if (index < 0 || index >= _photos.length) return;
    final path = _pathAt(index);
    if (_decoded.containsKey(path) || _inFlight.contains(path)) return;
    _inFlight.add(path);
    try {
      // A large bounded preview, never the grid thumbnail.
      final data = await _viewerBytes(index);
      if (!mounted) return;
      final size = MediaQuery.sizeOf(context);
      final image = await _decoder.decode(
        data.bytes,
        path: path,
        viewportLongestEdge: math.max(size.width, size.height).round(),
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      );
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() {
        _errors.remove(path);
        _decoded[path] = image;
      });
      _enforcePixelBudget(_current);
    } on ImageDecodeException catch (e) {
      // Report it. Swallowing this is what leaves the viewer stuck on the
      // placeholder and looking blurry.
      if (mounted) {
        setState(() => _errors[path] = _decodeMessage(path, e));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errors[path] = _friendly(e));
      }
    } finally {
      _inFlight.remove(path);
    }
  }

  String _decodeMessage(String path, ImageDecodeException e) {
    return 'This image could not be decoded on this device. '
        'It may use a format or size this platform cannot render.';
  }

  /// Drops frames outside the `current Â± _decodeWindow` range.
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

  /// Keeps decoded RGBA frames within [ImageDecodePolicy.decodedFramePixelBudget]
  /// by releasing the neighbour furthest from the visible page.
  void _enforcePixelBudget(int index) {
    final currentPath = _pathAt(index);
    var held = _decoded.values.fold<int>(
      0,
      (sum, image) => sum + image.width * image.height,
    );
    if (held <= ImageDecodePolicy.decodedFramePixelBudget) return;

    final candidates = _decoded.keys.where((p) => p != currentPath).toList()
      ..sort(
          (a, b) => _distanceFrom(b, index).compareTo(_distanceFrom(a, index)));
    for (final path in candidates) {
      if (held <= ImageDecodePolicy.decodedFramePixelBudget) break;
      final image = _decoded.remove(path);
      if (image != null) {
        held -= image.width * image.height;
        image.dispose();
      }
    }
    if (mounted) setState(() {});
  }

  int _distanceFrom(String path, int index) {
    final at = _photos.indexWhere((p) => (p['path'] ?? '').toString() == path);
    return at < 0 ? 1 << 30 : (at - index).abs();
  }

  void _retry(int index) {
    final path = _pathAt(index);
    // Drop the cached bytes too: re-decoding what we already hold would fail
    // exactly the same way, so a Retry that only reset the error flag would be
    // a button that can never succeed.
    widget.images
      ..forget(_previewKey(index))
      ..forget(_originalKey(index));
    setState(() {
      _errors.remove(path);
      _decoded.remove(path)?.dispose();
    });
    _ensureDecoded(index);
  }

  String _friendly(Object e) {
    if (e is ApiException) {
      if (e.status == 404) return 'This photo is no longer on the server.';
      if (e.status == 401) return 'Your session expired. Sign in again.';
      return e.message;
    }
    if (e is SaveException) return e.message;
    return 'The photo could not be loaded. Check your connection.';
  }

  void _onPageChanged(int index) {
    setState(() {
      _current = index;
      _zoomed = false;
    });
    _zoomHintTimer?.cancel();
    _zoomHintVisible = false;
    _zoomLevel.value = 1;
    _showChrome();
    _prefetchAround(index);
  }

  /// One dark tonal scheme for every overlay that floats above the media.
  ThemeData _chromeTheme(BuildContext context) => Theme.of(context).copyWith(
        brightness: Brightness.dark,
        colorScheme: AppColors.scheme(Brightness.dark),
      );

  /// Keeps the transient zoom chip in sync with the active page only.
  void _onZoomChanged(int index, bool zoomed, double level) {
    if (index != _current) return;
    setState(() {
      _zoomed = zoomed;
      if (!zoomed) _chromeVisible = true;
      _zoomHintVisible = true;
    });
    _zoomLevel.value = level;
    _zoomHintTimer?.cancel();
    _zoomHintTimer = Timer(AppMotion.slow + AppMotion.normal, () {
      if (!mounted) return;
      setState(() => _zoomHintVisible = false);
    });
  }

  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
    if (_chromeVisible) _scheduleChromeHide();
  }

  void _showChrome() {
    if (!mounted) return;
    setState(() => _chromeVisible = true);
    _scheduleChromeHide();
  }

  void _scheduleChromeHide() {
    _chromeHideTimer?.cancel();
    _chromeHideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || _zoomed) return;
      setState(() => _chromeVisible = false);
    });
  }

  void _toggleZoom() {
    _zoomSignal.value++;
    _showChrome();
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
    showNexaFormSheet<void>(
      context,
      builder: (_) => FileShareSheet(
        api: widget.api,
        files: [FileEntry.fromJson(Map<String, dynamic>.from(p))],
      ),
    );
  }

  Future<void> _deleteCurrent() async {
    final index = _current;
    final name =
        _photos[index]['name']?.toString() ?? _pathAt(index).split('/').last;
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

  Map<String, dynamic> get _currentEntry => _photos[_current];

  /// Google Photos shows time and place above the image, not a filename. This
  /// library has no location field, so the server's modified time is the
  /// glanceable metadata and the full name stays in the details sheet.
  String _dateLabel(BuildContext context) {
    final modified = DateTime.tryParse(
      _currentEntry['modified_at']?.toString() ?? '',
    );
    if (modified == null) return 'Photo';
    final local = modified.toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: true,
    );
    return '${local.day} ${months[local.month - 1]} ${local.year} · $time';
  }

  /// Swipe-up details mirror Google Photos: metadata lives in a draggable
  /// tonal sheet, while the photo itself stays unobstructed.
  Future<void> _showDetails() async {
    // Snapshot the entry: the page can change while the sheet is open.
    final entry = Map<String, dynamic>.from(_currentEntry);
    final path = _pathAt(_current);
    final position = '${_current + 1} of ${_photos.length}';
    final modified = DateTime.tryParse(entry['modified_at']?.toString() ?? '');
    final scheme = Theme.of(context).colorScheme;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      showDragHandle: true,
      useSafeArea: true,
      barrierColor: AppColors.scrimFor(scheme.brightness),
      // Same tonal role as NexaSurfaceLevel.modal; the sheet supplies the
      // shape, elevation and Material drag handle.
      backgroundColor: nexaSurfaceColor(
        NexaSurfaceLevel.modal,
        scheme.brightness,
      ),
      sheetAnimationStyle: AppMotion.reducedMotion(context)
          ? const AnimationStyle(
              duration: Duration.zero,
              reverseDuration: Duration.zero,
            )
          : AppMotion.sheetAnimationStyle,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom +
                AppDimens.space24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NexaSheetHeader(
                title: 'Details',
                subtitle: position,
                onClose: () => Navigator.pop(sheetContext),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.pageMargin,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DetailRow(label: 'Name', value: path.split('/').last),
                    if (modified != null)
                      _DetailRow(
                        label: 'Modified',
                        value: Format.shortDateTime(modified.toLocal()),
                      ),
                    if (entry['size'] != null)
                      _DetailRow(
                        label: 'Size',
                        value: Format.bytes(entry['size']),
                      ),
                    _DetailRow(label: 'Position', value: position),
                  ],
                ),
              ),
              const SizedBox(height: AppDimens.space8),
            ],
          ),
        ),
      ),
    );
  }

  void _showActions() {
    showNexaSheet<void>(
      context,
      builder: (sheetContext) => NexaSheetBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NexaSheetHeader(
              title: _pathAt(_current).split('/').last,
              subtitle: '${_current + 1} of ${_photos.length}',
            ),
            NexaSheetAction(
              icon: Icons.info_outline_rounded,
              title: 'Details',
              onTap: () {
                Navigator.pop(sheetContext);
                _showDetails();
              },
            ),
            NexaSheetAction(
              icon: _zoomed ? Icons.zoom_out_rounded : Icons.zoom_in_rounded,
              title: _zoomed ? 'Zoom out' : 'Zoom in',
              onTap: () {
                Navigator.pop(sheetContext);
                _toggleZoom();
              },
            ),
            if (_photos.length > 1)
              NexaSheetAction(
                icon: _filmstripVisible
                    ? Icons.view_stream_outlined
                    : Icons.view_module_outlined,
                title: _filmstripVisible ? 'Hide filmstrip' : 'Show filmstrip',
                onTap: () {
                  Navigator.pop(sheetContext);
                  setState(() => _filmstripVisible = !_filmstripVisible);
                  _showChrome();
                },
              ),
            NexaSheetAction(
              icon: Icons.download_outlined,
              title: 'Save to device',
              onTap: () {
                Navigator.pop(sheetContext);
                _downloadCurrent();
              },
            ),
            NexaSheetAction(
              icon: Icons.share_outlined,
              title: 'Share',
              onTap: () {
                Navigator.pop(sheetContext);
                _shareCurrent();
              },
            ),
            NexaSheetAction(
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

  /// During a Hero flight the destination is a moving rect, so the shuttle
  /// paints the same bounded grid thumbnail the user just tapped. The full
  /// preview is never fetched just to make a transition look good.
  Widget _heroShuttle(
    BuildContext context,
    HeroFlightDirection direction,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
    String path,
  ) {
    final bytes = widget.thumbnailLookup?.call(path);
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        excludeFromSemantics: true,
      );
    }
    // No grid thumbnail (e.g. opened from a file picker): fall back to the
    // destination hero's own child, which is what Flutter does by default.
    final hero = toHeroContext.widget;
    return hero is Hero ? hero.child : const SizedBox.expand();
  }

  @override
  Widget build(BuildContext context) {
    // Immersive media chrome: a full dark ColorScheme so tonal controls and
    // metadata resolve together over the user's photo.
    final darkChrome = _chromeTheme(context);
    final compact =
        MediaQuery.sizeOf(context).width < AppDimens.breakpointCompactMax;
    final canDismiss = compact && !_zoomed && !_filmstripVisible;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: _SwipeDismissLayer(
              canDismiss: canDismiss,
              canShowDetails: !_zoomed && !_filmstripVisible,
              onDismiss: () {
                if (mounted) Navigator.of(context).maybePop();
              },
              onDetails: _showDetails,
              child: PageView.builder(
                controller: _controller,
                onPageChanged: _onPageChanged,
                itemCount: _photos.length,
                itemBuilder: (context, i) {
                  final path = _pathAt(i);
                  final error = _errors[path];
                  final image = _decoded[path];
                  final Widget imageLayer;
                  if (error != null) {
                    imageLayer = _ViewerError(
                      key: ValueKey('error:$path'),
                      message: error,
                      onRetry: () => _retry(i),
                    );
                  } else if (image == null) {
                    imageLayer = _LoadingPage(
                      key: ValueKey('loading:$path'),
                      thumbnail: widget.thumbnailLookup?.call(path),
                    );
                  } else {
                    imageLayer = _ZoomablePhoto(
                      key: ValueKey('original:$path'),
                      image: image,
                      active: i == _current,
                      zoomSignal: _zoomSignal,
                      onTap: _toggleChrome,
                      onZoomedChanged: (zoomed) =>
                          _onZoomChanged(i, zoomed, _zoomLevel.value),
                      onScaleChanged: (level) {
                        if (i == _current) _zoomLevel.value = level;
                      },
                    );
                  }
                  // The Hero owns the page for its whole lifetime (loading,
                  // decoded or error), so the grid -> viewer flight is already
                  // available on the first frame. Unique tags per path avoid
                  // conflicts while PageView builds neighbouring pages.
                  return HeroMode(
                    enabled: !AppMotion.reducedMotion(context),
                    child: Hero(
                      key: ValueKey('photoHero:$path'),
                      tag: 'photo:$path',
                      flightShuttleBuilder: (context, animation, direction,
                              fromHeroContext, toHeroContext) =>
                          _heroShuttle(
                        context,
                        direction,
                        fromHeroContext,
                        toHeroContext,
                        path,
                      ),
                      child: KeyedSubtree(
                        key: ValueKey('photoHeroChild:$path'),
                        child: imageLayer,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: SafeArea(
              bottom: false,
              child: IgnorePointer(
                ignoring: !_chromeVisible,
                child: AnimatedOpacity(
                  opacity: _chromeVisible ? 1 : 0,
                  duration: AppMotion.resolve(context, AppMotion.fast),
                  curve: AppMotion.standard,
                  child: Theme(
                    data: darkChrome,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimens.space8,
                        vertical: AppDimens.space8,
                      ),
                      child: Row(
                        children: [
                          _ChromeIcon(
                            icon: Icons.arrow_back_rounded,
                            tooltip: MaterialLocalizations.of(context)
                                .backButtonTooltip,
                            onTap: () => Navigator.of(context).maybePop(),
                          ),
                          const SizedBox(width: AppDimens.space8),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _dateLabel(context),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: AppTextStyle.labelMedium.copyWith(
                                    color: Colors.white,
                                    shadows: const [
                                      Shadow(
                                        color: AppColors.scrim,
                                        blurRadius: AppDimens.space6,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: AppDimens.space2),
                                Semantics(
                                  label:
                                      'Photo ${_current + 1} of ${_photos.length}',
                                  child: ExcludeSemantics(
                                    child: Text(
                                      '${_current + 1} of ${_photos.length}',
                                      style: AppTextStyle.caption.copyWith(
                                        color: Colors.white70,
                                        shadows: const [
                                          Shadow(
                                            color: AppColors.scrim,
                                            blurRadius: AppDimens.space6,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _ChromeIcon(
                            icon: Icons.more_vert_rounded,
                            tooltip: 'Photo options',
                            onTap: _showActions,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: MediaQuery.paddingOf(context).top +
                AppDimens.space56 +
                AppDimens.space16,
            child: _ZoomIndicator(
              visible: _zoomHintVisible,
              zoomLevel: _zoomLevel,
              theme: darkChrome,
            ),
          ),
          if (_photos.length > 1 && _filmstripVisible)
            _Filmstrip(
              visible: _chromeVisible,
              count: _photos.length,
              current: _current,
              pathFor: _pathAt,
              thumbnailFor: widget.thumbnailLookup,
              onJump: (index) {
                _controller.jumpToPage(index);
                _showChrome();
              },
            ),
          _BottomBar(
            visible: _chromeVisible,
            onDownload: _downloadCurrent,
            onShare: _shareCurrent,
            onDetails: _showDetails,
            onDelete: _deleteCurrent,
          ),
        ],
      ),
    );
  }
}

/// Placeholder shown while the viewer preview downloads.
///
/// The grid thumbnail, when available, is drawn strongly blurred and dimmed
/// behind the spinner â the standard "progressive loading" treatment. That
/// reads unambiguously as *loading*; showing a sharp but small preview instead
/// reads as "the photo is broken and looks blurry".
class _LoadingPage extends StatelessWidget {
  final Uint8List? thumbnail;
  const _LoadingPage({super.key, this.thumbnail});

  @override
  Widget build(BuildContext context) {
    final preview = thumbnail;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (preview != null)
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Opacity(
              opacity: 0.45,
              child: Image.memory(
                preview,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                gaplessPlayback: true,
                cacheWidth: 1024,
                excludeFromSemantics: true,
              ),
            ),
          ),
        Container(color: AppColors.scrim),
        Semantics(
          label: 'Loading photo',
          child: Center(
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2,
            ),
          ),
        ),
      ],
    );
  }
}

/// Graceful failure with a clear cause and a retry affordance.
class _ViewerError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ViewerError({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).copyWith(
      brightness: Brightness.dark,
      colorScheme: AppColors.scheme(Brightness.dark),
    );
    final scheme = dark.colorScheme;
    return Theme(
      data: dark,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.space32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.broken_image_outlined,
                color: scheme.onSurfaceVariant,
                size: AppDimens.iconTileLarge,
              ),
              const SizedBox(height: AppDimens.space16),
              Text(
                'Can\u2019t open this photo',
                textAlign: TextAlign.center,
                style: AppTextStyle.sectionHeader.copyWith(
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: AppDimens.space8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTextStyle.rowSubtitle.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppDimens.space20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(
                  Icons.refresh_rounded,
                  size: AppDimens.iconSmall,
                ),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Transient zoom chip. It is deliberately not a second control surface: it
/// only reports the current multiplier, then fades away with the chrome's
/// timing. A tonal floating NexaSurface keeps it legible on bright photos.
class _ZoomIndicator extends StatelessWidget {
  final bool visible;
  final ValueNotifier<double> zoomLevel;
  final ThemeData theme;

  const _ZoomIndicator({
    required this.visible,
    required this.zoomLevel,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: true,
      child: Center(
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: AppMotion.resolve(context, AppMotion.fast),
          curve: AppMotion.curveFor(context, AppMotion.fade),
          child: Theme(
            data: theme,
            child: ValueListenableBuilder<double>(
              valueListenable: zoomLevel,
              builder: (context, level, _) {
                final label = '${level.toStringAsFixed(1)}×';
                final scheme = Theme.of(context).colorScheme;
                return Semantics(
                  label: 'Zoom $label',
                  container: true,
                  child: ExcludeSemantics(
                    child: NexaSurface(
                      level: NexaSurfaceLevel.floating,
                      radius: AppDimens.radiusPill,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimens.space12,
                        vertical: AppDimens.space6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.zoom_in_rounded,
                            size: AppDimens.iconSmall,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: AppDimens.space6),
                          Text(
                            label,
                            style: AppTextStyle.labelMedium.copyWith(
                              color: scheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Owns the mobile swipe-to-dismiss gesture around the page view.
///
/// Vertical drags are only registered while the photo is at fit scale and no
/// browse layer is open. Horizontal PageView swipes, pinch zoom and double-tap
/// keep their own recognizers; `InteractiveViewer` disables panning at fit so
/// it cannot steal the downward drag.
class _SwipeDismissLayer extends StatefulWidget {
  final bool canDismiss;
  final bool canShowDetails;
  final VoidCallback onDismiss;
  final VoidCallback onDetails;
  final Widget child;

  const _SwipeDismissLayer({
    required this.canDismiss,
    required this.canShowDetails,
    required this.onDismiss,
    required this.onDetails,
    required this.child,
  });

  @override
  State<_SwipeDismissLayer> createState() => _SwipeDismissLayerState();
}

class _SwipeDismissLayerState extends State<_SwipeDismissLayer>
    with SingleTickerProviderStateMixin {
  double _drag = 0;
  double _settleFrom = 0;
  AnimationController? _settle;

  @override
  void didUpdateWidget(covariant _SwipeDismissLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_drag != 0 && !widget.canDismiss) {
      _settle?.stop();
      _settle?.dispose();
      _settle = null;
      _drag = 0;
    }
  }

  @override
  void dispose() {
    _settle?.dispose();
    super.dispose();
  }

  void _settleBack() {
    if (_drag <= 0) return;
    if (AppMotion.reducedMotion(context)) {
      _settle?.stop();
      setState(() => _drag = 0);
      return;
    }
    _settleFrom = _drag;
    _settle?.dispose();
    _settle = AnimationController(vsync: this, duration: AppMotion.normal);
    _settle!.addListener(() {
      if (!mounted) return;
      setState(() => _drag = _settleFrom * (1 - _settle!.value));
    });
    _settle!.addStatusListener((status) {
      if (status.isCompleted || status.isDismissed) {
        _settle?.dispose();
        _settle = null;
      }
    });
    _settle!.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    final maxDrag = height * 0.65;
    final gesturesEnabled = widget.canDismiss || widget.canShowDetails;

    Widget content = widget.child;
    if (_drag > 0 && !AppMotion.reducedMotion(context)) {
      final progress = (_drag / height).clamp(0.0, 1.0);
      content = Opacity(
        opacity: (1 - progress * 0.5).clamp(0.35, 1.0),
        child: Transform.translate(
          offset: Offset(0, _drag),
          child: content,
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: gesturesEnabled
          ? (_) {
              _settle?.stop();
              if (_drag != 0) setState(() => _drag = 0);
            }
          : null,
      onVerticalDragUpdate: widget.canDismiss
          ? (details) {
              if (details.delta.dy <= 0 && _drag <= 0) return;
              setState(() {
                _drag = (_drag + details.delta.dy).clamp(0.0, maxDrag);
              });
            }
          : null,
      onVerticalDragEnd: gesturesEnabled
          ? (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (widget.canDismiss && _drag > 0) {
                if (_drag > height * 0.16 || (velocity > 650 && _drag > 20)) {
                  setState(() => _drag = 0);
                  widget.onDismiss();
                } else {
                  _settleBack();
                }
                return;
              }
              // Google Photos reveals metadata with an upward swipe.
              if (widget.canShowDetails && velocity < -500) {
                widget.onDetails();
              }
            }
          : null,
      onVerticalDragCancel: gesturesEnabled ? () => _settleBack() : null,
      child: content,
    );
  }
}

/// A small neighbourhood of nearby photos. It gives the immersive viewer a
/// Google Photos sense of place without adding permanent prev/next arrows.
class _Filmstrip extends StatelessWidget {
  final bool visible;
  final int count;
  final int current;
  final String Function(int index) pathFor;
  final Uint8List? Function(String path)? thumbnailFor;
  final ValueChanged<int> onJump;

  const _Filmstrip({
    required this.visible,
    required this.count,
    required this.current,
    required this.pathFor,
    required this.thumbnailFor,
    required this.onJump,
  });

  @override
  Widget build(BuildContext context) {
    final start = math.max(0, current - 2);
    final end = math.min(count - 1, current + 2);
    final indices = List<int>.generate(end - start + 1, (i) => start + i);
    final duration = AppMotion.resolve(context, AppMotion.fast);

    return Positioned(
      left: 0,
      right: 0,
      // Sits directly above the action row; no enclosing card or bar.
      bottom: MediaQuery.paddingOf(context).bottom +
          AppDimens.space56 +
          AppDimens.space56,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: duration,
          curve: AppMotion.standard,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.space16,
                  ),
                  itemCount: indices.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: AppDimens.space8),
                  itemBuilder: (context, position) {
                    final index = indices[position];
                    final bytes = thumbnailFor?.call(pathFor(index));
                    final selected = index == current;
                    return AnimatedScale(
                      scale: selected ? 1 : 0.86,
                      duration: duration,
                      curve: AppMotion.standard,
                      child: AnimatedOpacity(
                        opacity: selected ? 1 : 0.7,
                        duration: duration,
                        child: SizedBox(
                          width: 64,
                          height: 64,
                          child: Material(
                            color: AppColors.canvasDark,
                            clipBehavior: Clip.antiAlias,
                            borderRadius:
                                BorderRadius.circular(AppDimens.radiusSmall),
                            child: InkWell(
                              onTap: () => onJump(index),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (bytes != null)
                                    Image.memory(
                                      bytes,
                                      fit: BoxFit.cover,
                                      gaplessPlayback: true,
                                    )
                                  else
                                    const Icon(
                                      Icons.image_outlined,
                                      color: Colors.white70,
                                      size: AppDimens.iconMedium,
                                    ),
                                  Positioned.fill(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(
                                          AppDimens.radiusSmall,
                                        ),
                                        border: Border.all(
                                          color: selected
                                              ? Colors.white
                                              : Colors.transparent,
                                          width: AppDimens.space2,
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
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A circular, scrim-backed control that floats over media instead of adding
/// another bar. The scrim exists only for legibility on bright images.
class _ChromeIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ChromeIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.scrim,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        color: Colors.white,
        icon: Icon(icon, size: AppDimens.iconMedium),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.space8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: AppDimens.space48 + AppDimens.space32,
            child: Text(
              label,
              style: AppTextStyle.caption.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppDimens.space8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppTextStyle.bodySmall.copyWith(color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

/// Google Photos-style bottom row: floating, labelled controls with no panel
/// behind them. The rounded backing belongs to the icon only, so the image is
/// never framed by another rectangle.
class _BottomBar extends StatelessWidget {
  final bool visible;
  final VoidCallback onDownload;
  final VoidCallback onShare;
  final VoidCallback onDetails;
  final VoidCallback onDelete;

  const _BottomBar({
    required this.visible,
    required this.onDownload,
    required this.onShare,
    required this.onDetails,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: AppDimens.space8,
      right: AppDimens.space8,
      bottom: MediaQuery.paddingOf(context).bottom + AppDimens.space12,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: AppMotion.resolve(context, AppMotion.fast),
          curve: AppMotion.standard,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _MediaAction(
                icon: Icons.share_outlined,
                label: 'Share',
                tooltip: 'Share',
                onTap: onShare,
              ),
              _MediaAction(
                icon: Icons.download_outlined,
                label: 'Save',
                tooltip: 'Save to device',
                onTap: onDownload,
              ),
              _MediaAction(
                icon: Icons.info_outline_rounded,
                label: 'Info',
                tooltip: 'Details',
                onTap: onDetails,
              ),
              _MediaAction(
                icon: Icons.delete_outline_rounded,
                label: 'Trash',
                tooltip: 'Move to Trash',
                onTap: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  const _MediaAction({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.space8,
            vertical: AppDimens.space4,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: const BoxDecoration(
                  color: AppColors.scrim,
                  shape: BoxShape.circle,
                ),
                child: SizedBox(
                  width: AppDimens.touchTarget,
                  height: AppDimens.touchTarget,
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: AppDimens.iconMedium,
                  ),
                ),
              ),
              const SizedBox(height: AppDimens.space6),
              Text(
                label,
                style: AppTextStyle.caption.copyWith(
                  color: Colors.white,
                  shadows: const [
                    Shadow(
                      color: AppColors.scrim,
                      blurRadius: AppDimens.space6,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZoomablePhoto extends StatefulWidget {
  final ui.Image image;
  final bool active;
  final ValueNotifier<int> zoomSignal;
  final VoidCallback onTap;
  final ValueChanged<bool> onZoomedChanged;
  final ValueChanged<double> onScaleChanged;

  const _ZoomablePhoto({
    super.key,
    required this.image,
    required this.active,
    required this.zoomSignal,
    required this.onTap,
    required this.onZoomedChanged,
    required this.onScaleChanged,
  });

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto>
    with SingleTickerProviderStateMixin {
  final TransformationController _transform = TransformationController();
  Size? _viewport;
  double _fit = 1;
  bool _fitted = false;

  /// Live sampler choice, so minifying a large photo uses mipmaps.
  ui.FilterQuality _quality = ui.FilterQuality.medium;

  late final AnimationController _zoomAnim;
  Matrix4Tween? _zoomTween;
  bool _zoomed = false;
  late final VoidCallback _zoomListener;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransformChanged);
    _zoomListener = () {
      if (widget.active && mounted) _toggleZoom();
    };
    widget.zoomSignal.addListener(_zoomListener);
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
    widget.zoomSignal.removeListener(_zoomListener);
    _transform.removeListener(_onTransformChanged);
    _zoomAnim.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final scale = _transform.value.getMaxScaleOnAxis();
    final next = ImageDecodePolicy.filterQualityForScale(scale);
    final zoomed = scale > _fit * 1.25;
    if (next != _quality && mounted) setState(() => _quality = next);
    if (_fit > 0) {
      widget.onScaleChanged.call((scale / _fit).clamp(0.1, 20.0));
    }
    if (zoomed != _zoomed) {
      _zoomed = zoomed;
      if (mounted) widget.onZoomedChanged.call(zoomed);
    }
  }

  Size get _photo =>
      Size(widget.image.width.toDouble(), widget.image.height.toDouble());

  double _fitFor(Size viewport, Size photo) {
    if (photo.width <= 0 || photo.height <= 0) return 1;
    return math
        .min(viewport.width / photo.width, viewport.height / photo.height)
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
    if (AppMotion.reducedMotion(context)) {
      _transform.value = end;
      _zoomTween = null;
      return;
    }
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
          onTap: widget.onTap,
          onDoubleTap: _toggleZoom,
          child: InteractiveViewer(
            transformationController: _transform,
            constrained: false,
            // At fit scale there is nothing to pan; leaving it off stops the
            // viewer competing with the mobile swipe-to-dismiss gesture.
            // Pinch, double-tap and the overflow zoom button are untouched.
            panEnabled: _zoomed,
            minScale: math.max(_fit * 0.9, 0.5),
            maxScale: math.max(_fit * 8, 1.4),
            clipBehavior: Clip.none,
            child: RawImage(
              image: widget.image,
              fit: BoxFit.none,
              filterQuality: _quality,
              isAntiAlias: true,
            ),
          ),
        );
      },
    );
  }
}
