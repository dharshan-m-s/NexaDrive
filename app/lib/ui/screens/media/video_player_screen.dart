import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_motion.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/models/file_entry.dart';
import '../../../core/utils/format.dart';
import '../../../services/api.dart';
import '../../../services/download_service.dart';
import '../../widgets/nexa_components.dart';

/// Immersive video player with floating, tonal controls.
///
/// Streams the clip from the server with the session's auth headers, so
/// seeking works through the server's byte-range support (no full download
/// before the first frame) and memory stays flat for long videos. Platforms
/// without a media backend fall back to an honest download flow.
class VideoPlayerScreen extends StatefulWidget {
  final FileEntry file;
  final Api api;

  const VideoPlayerScreen({super.key, required this.file, required this.api});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  bool _initializing = true;
  bool _controlsVisible = true;
  bool _fullscreen = false;
  String? _error;
  Timer? _hideTimer;

  double _speed = 1.0;
  double _volume = 1.0;
  bool _dragging = false;
  double _dragFraction = 0;

  static const _speeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.removeListener(_onListen);
    _controller?.dispose();
    _restoreSystemChrome();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() {
      _initializing = true;
      _error = null;
    });
    try {
      final controller = VideoPlayerController.networkUrl(
        widget.api.fileDownloadUri(widget.file.path),
        httpHeaders: widget.api.authHeaders,
      );
      _controller = controller;
      await controller.initialize();
      await controller.setVolume(_volume);
      await controller.setPlaybackSpeed(_speed);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      controller.addListener(_onListen);
      setState(() => _initializing = false);
      _scheduleHide();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendly(e);
        _initializing = false;
      });
    }
  }

  String _friendly(Object e) {
    if (e is ApiException) {
      if (e.status == 401) return 'Your session expired. Sign in again.';
      if (e.status == 404) return 'This video is no longer on the server.';
      return e.message;
    }
    final text = e.toString();
    if (text.contains('Unsupported') || text.contains('format')) {
      return 'This device has no decoder for ${widget.file.name.split('.').last.toUpperCase()} video. '
          'Save it and open it with another player.';
    }
    return 'The video stream could not be started. Check your connection and try again.';
  }

  void _onListen() {
    if (!mounted) return;
    setState(() {});
    if (_controller?.value.isPlaying == true) _scheduleHide();
  }

  /// Arms the auto-hide countdown.
  ///
  /// `restart: false` (the default) is what the controller listener uses. The
  /// listener fires on every playback tick, so restarting the timer there would
  /// push the deadline back forever and the controls would never hide â which
  /// is exactly what a "controls stay on screen" bug looks like. Only explicit
  /// user interaction resets the countdown.
  void _scheduleHide({bool restart = false}) {
    if (!restart && (_hideTimer?.isActive ?? false)) return;
    _hideTimer?.cancel();
    if (!mounted) return;
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (_controller?.value.isPlaying == true && !_dragging) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide(restart: true);
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      await controller.pause();
      setState(() => _controlsVisible = true);
      _hideTimer?.cancel();
    } else {
      await controller.play();
      _scheduleHide(restart: true);
    }
  }

  Future<void> _setMuted(bool mute) async {
    final controller = _controller;
    if (controller == null) return;
    final volume = mute ? 0.0 : 1.0;
    setState(() => _volume = volume);
    await controller.setVolume(volume);
    _scheduleHide(restart: true);
  }

  Future<void> _setSpeed(double speed) async {
    final controller = _controller;
    if (controller == null) return;
    setState(() => _speed = speed);
    await controller.setPlaybackSpeed(speed);
    _scheduleHide(restart: true);
  }

  /// Google Photos-style 10-second nudges, clamped to the real duration.
  Future<void> _seekBy(Duration delta) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    var target = controller.value.position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (target > controller.value.duration) target = controller.value.duration;
    await controller.seekTo(target);
    _scheduleHide(restart: true);
  }

  Future<void> _toggleFullscreen() async {
    final next = !_fullscreen;
    setState(() => _fullscreen = next);
    if (next) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      _restoreSystemChrome();
    }
  }

  void _restoreSystemChrome() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<void> _saveToDevice() async {
    try {
      final result = await DownloadService(widget.api).saveAs(
        remotePath: widget.file.path,
        fileName: widget.file.name,
      );
      if (!mounted) return;
      _toast(result == null
          ? 'Download cancelled'
          : 'Saved to ${result.location}');
    } on SaveCancelled {
      if (mounted) _toast('Download cancelled');
    } catch (e) {
      if (mounted) _toast(e.toString());
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final value = controller?.value;
    final initialized = value?.isInitialized == true;
    // Video runs on a black canvas: use a complete dark ColorScheme so the
    // page header, empty states and tonal control surfaces resolve together.
    final darkTheme = Theme.of(context).copyWith(
      brightness: Brightness.dark,
      colorScheme: AppColors.scheme(Brightness.dark),
    );

    final body = _initializing
        ? const Center(
            child:
                CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
          )
        : _error != null
            ? Center(
                child: NexaEmptyState(
                  icon: Icons.movie_outlined,
                  title: 'Can\u2019t play this video',
                  hint: _error,
                  actionLabel: 'Retry',
                  onAction: _init,
                ),
              )
            : initialized
                ? _buildPlayer(controller!, value!)
                : const SizedBox.shrink();

    return PopScope(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _fullscreen) _toggleFullscreen();
      },
      child: Scaffold(
        backgroundColor: AppColors.canvasDark,
        body: SafeArea(
          top: !_fullscreen,
          bottom: false,
          child: Theme(
            data: darkTheme,
            child: Stack(
              children: [
                Positioned.fill(child: body),
                _videoTopChrome(context),
                if (initialized) _videoControls(context, controller!, value!),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlayer(
    VideoPlayerController controller,
    VideoPlayerValue value,
  ) {
    final aspect = value.aspectRatio > 0 ? value.aspectRatio : 16 / 9;
    final video = Center(
      child: AspectRatio(
        aspectRatio: aspect,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(controller),
            if (value.isBuffering && value.isPlaying)
              const Center(
                child: CircularProgressIndicator(
                  color: Colors.white70,
                  strokeWidth: 2,
                ),
              ),
            if (!value.isPlaying && !value.isBuffering)
              _PlayOverlay(onTap: _togglePlay),
          ],
        ),
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleControls,
      child: Stack(children: [Positioned.fill(child: video)]),
    );
  }

  /// Google Photos-style metadata overlay: no header slab, just a floating
  /// back control, the clip's date/title, and the advanced controls menu.
  Widget _videoTopChrome(BuildContext context) {
    final modified = widget.file.modified?.toLocal();
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: SafeArea(
        bottom: false,
        child: IgnorePointer(
          ignoring: !_controlsVisible,
          child: AnimatedOpacity(
            opacity: _controlsVisible ? 1 : 0,
            duration: AppMotion.resolve(context, AppMotion.fast),
            curve: AppMotion.standard,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.space8,
                vertical: AppDimens.space8,
              ),
              child: Row(
                children: [
                  _FloatingIcon(
                    icon: Icons.arrow_back_rounded,
                    tooltip:
                        MaterialLocalizations.of(context).backButtonTooltip,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: AppDimens.space8),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.file.name,
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
                        if (modified != null) ...[
                          const SizedBox(height: AppDimens.space2),
                          Text(
                            Format.shortDateTime(modified),
                            style: AppTextStyle.caption
                                .copyWith(color: Colors.white70),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Material(
                    color: AppColors.scrim,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: PopupMenuButton<_VideoTopAction>(
                      tooltip: 'More controls',
                      color: AppColors.canvasDark,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: AppDimens.touchTarget * 4,
                      ),
                      icon: const SizedBox(
                        width: AppDimens.touchTarget,
                        height: AppDimens.touchTarget,
                        child: Icon(
                          Icons.more_vert_rounded,
                          color: Colors.white,
                          size: AppDimens.iconMedium,
                        ),
                      ),
                      onSelected: (action) {
                        switch (action) {
                          case _VideoTopAction.save:
                            _saveToDevice();
                          case _VideoTopAction.mute:
                            _setMuted(_volume > 0);
                          case _VideoTopAction.speed1:
                            _setSpeed(1.0);
                          case _VideoTopAction.speed1_5:
                            _setSpeed(1.5);
                          case _VideoTopAction.speed2:
                            _setSpeed(2.0);
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: _VideoTopAction.save,
                          child: const Text('Save to device'),
                        ),
                        PopupMenuItem(
                          value: _VideoTopAction.mute,
                          child: Text(_volume > 0 ? 'Mute' : 'Unmute'),
                        ),
                        const PopupMenuDivider(),
                        for (final speed in _speeds)
                          if (speed == 1.0 || speed == 1.5 || speed == 2.0)
                            PopupMenuItem(
                              value: switch (speed) {
                                1.0 => _VideoTopAction.speed1,
                                1.5 => _VideoTopAction.speed1_5,
                                _ => _VideoTopAction.speed2,
                              },
                              child: Row(
                                children: [
                                  Text('${speed}x speed'),
                                  if ((_speed - speed).abs() < 0.001)
                                    const Padding(
                                      padding: EdgeInsets.only(
                                        left: AppDimens.space8,
                                      ),
                                      child: Icon(
                                        Icons.check_rounded,
                                        size: AppDimens.iconSmall,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                      ],
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

  /// A minimal transport surface: progress and controls float directly over
  /// the video. Volume and speed live in the top overflow, never in a panel.
  Widget _videoControls(
    BuildContext context,
    VideoPlayerController controller,
    VideoPlayerValue value,
  ) {
    final duration = value.duration;
    final fraction = _dragging
        ? _dragFraction
        : duration.inMilliseconds > 0
            ? (value.position.inMilliseconds / duration.inMilliseconds)
                .clamp(0.0, 1.0)
                .toDouble()
            : 0.0;
    final shownPosition = _dragging
        ? Duration(milliseconds: (fraction * duration.inMilliseconds).round())
        : value.position;
    final remaining = duration - shownPosition;

    return Positioned(
      left: AppDimens.space16,
      right: AppDimens.space16,
      bottom: MediaQuery.paddingOf(context).bottom + AppDimens.space16,
      child: AnimatedSlide(
        offset: _controlsVisible ? Offset.zero : const Offset(0, 0.08),
        duration: AppMotion.resolve(context, AppMotion.fast),
        curve: AppMotion.standard,
        child: AnimatedOpacity(
          opacity: _controlsVisible ? 1 : 0,
          duration: AppMotion.resolve(context, AppMotion.fast),
          curve: AppMotion.standard,
          child: IgnorePointer(
            ignoring: !_controlsVisible,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      Format.duration(shownPosition),
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
                    Text(
                      duration == Duration.zero
                          ? '--:--'
                          : '−${Format.duration(remaining.isNegative ? Duration.zero : remaining)}',
                      style: AppTextStyle.labelSmall
                          .copyWith(color: Colors.white70),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white30,
                    thumbColor: Colors.white,
                    overlayColor: Colors.white24,
                    trackHeight: AppDimens.space2,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: AppDimens.space4,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: AppDimens.space12,
                    ),
                  ),
                  child: Semantics(
                    label: 'Seek video',
                    child: Slider(
                      value: fraction,
                      onChangeStart: (_) => setState(() => _dragging = true),
                      onChanged: (v) => setState(() => _dragFraction = v),
                      onChangeEnd: (v) async {
                        setState(() => _dragging = false);
                        final target = Duration(
                          milliseconds: (v * duration.inMilliseconds).round(),
                        );
                        await controller.seekTo(target);
                        _scheduleHide(restart: true);
                      },
                    ),
                  ),
                ),
                Row(
                  children: [
                    _FloatingIcon(
                      icon: Icons.replay_10_rounded,
                      tooltip: 'Back 10 seconds',
                      onTap: () => _seekBy(const Duration(seconds: -10)),
                    ),
                    const SizedBox(width: AppDimens.space12),
                    _FloatingIcon(
                      icon: value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      tooltip: value.isPlaying ? 'Pause' : 'Play',
                      onTap: _togglePlay,
                      large: true,
                    ),
                    const SizedBox(width: AppDimens.space12),
                    _FloatingIcon(
                      icon: Icons.forward_10_rounded,
                      tooltip: 'Forward 10 seconds',
                      onTap: () => _seekBy(const Duration(seconds: 10)),
                    ),
                    const Spacer(),
                    _FloatingIcon(
                      icon: _fullscreen
                          ? Icons.fullscreen_exit_rounded
                          : Icons.fullscreen_rounded,
                      tooltip: _fullscreen ? 'Exit full screen' : 'Full screen',
                      onTap: _toggleFullscreen,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _VideoTopAction { save, mute, speed1, speed1_5, speed2 }

/// Floating, scrim-backed control used by the transparent video chrome.
class _FloatingIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Future<void> Function()? onTap;
  final bool large;

  const _FloatingIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = large ? AppDimens.touchTargetLarge : AppDimens.touchTarget;
    return Semantics(
      button: true,
      label: tooltip,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.scrim,
          shape: BoxShape.circle,
        ),
        child: SizedBox(
          width: size,
          height: size,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Tooltip(
              message: tooltip,
              child: Icon(
                icon,
                color: Colors.white,
                size: large ? AppDimens.iconTile : AppDimens.iconMedium,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayOverlay extends StatelessWidget {
  final Future<void> Function() onTap;
  const _PlayOverlay({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Play',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: AppDimens.iconHero,
          height: AppDimens.iconHero,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            // Semantic scrim: this control sits directly over user media.
            color: AppColors.scrim,
          ),
          child: const Icon(
            Icons.play_arrow_rounded,
            color: Colors.white,
            size: AppDimens.iconTileLarge,
          ),
        ),
      ),
    );
  }
}
