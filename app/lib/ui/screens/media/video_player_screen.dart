import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_motion.dart';
import '../../../core/models/file_entry.dart';
import '../../../core/utils/format.dart';
import '../../../services/api.dart';
import '../../../services/download_service.dart';
import '../../widgets/one_ui_empty_state.dart';

/// One UI video player.
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

  void _scheduleHide() {
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
    if (_controlsVisible) _scheduleHide();
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
      _scheduleHide();
    }
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
      _toast(result == null ? 'Download cancelled' : 'Saved to ${result.location}');
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

    return PopScope(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _fullscreen) _toggleFullscreen();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: _fullscreen
            ? null
            : AppBar(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                title: Text(
                  widget.file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                actions: [
                  IconButton(
                    tooltip: 'Save to device',
                    onPressed: _saveToDevice,
                    icon: const Icon(Icons.download_outlined, color: Colors.white),
                  ),
                ],
              ),
        body: SafeArea(
          top: _fullscreen,
          child: _initializing
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : _error != null
                  ? Center(
                      child: OneUiEmptyState(
                        icon: Icons.movie_outlined,
                        title: 'Can\u2019t play this video',
                        hint: _error,
                        actionLabel: 'Retry',
                        onAction: _init,
                      ),
                    )
                  : initialized
                      ? _buildPlayer(controller!, value!)
                      : const SizedBox.shrink(),
        ),
      ),
    );
  }

  Widget _buildPlayer(VideoPlayerController controller, VideoPlayerValue value) {
    final aspect = value.aspectRatio > 0 ? value.aspectRatio : 16 / 9;
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

    final video = Center(
      child: AspectRatio(
        aspectRatio: aspect,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(controller),
            if (value.isBuffering && value.isPlaying)
              const Center(
                child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2),
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
      child: Stack(
        children: [
          Positioned.fill(child: video),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: AppMotion.resolve(context, AppMotion.fast),
              curve: AppMotion.standard,
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.66),
                  padding: const EdgeInsets.fromLTRB(
                    AppDimens.space8,
                    AppDimens.space8,
                    AppDimens.space8,
                    0,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            tooltip: value.isPlaying ? 'Pause' : 'Play',
                            onPressed: _togglePlay,
                            color: Colors.white,
                            iconSize: 34,
                            icon: Icon(
                              value.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                          ),
                          Text(
                            Format.duration(shownPosition),
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: const SliderThemeData(
                                activeTrackColor: AppColors.accentDark,
                                inactiveTrackColor: Colors.white24,
                                thumbColor: AppColors.accentDark,
                                trackHeight: 3,
                                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                              ),
                              child: Slider(
                                value: fraction,
                                onChangeStart: (_) =>
                                    setState(() => _dragging = true),
                                onChanged: (v) => setState(() => _dragFraction = v),
                                onChangeEnd: (v) async {
                                  setState(() => _dragging = false);
                                  final target = Duration(
                                    milliseconds:
                                        (v * duration.inMilliseconds).round(),
                                  );
                                  await controller.seekTo(target);
                                },
                              ),
                            ),
                          ),
                          Text(
                            duration == Duration.zero
                                ? '--:--'
                                : Format.duration(duration),
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                          IconButton(
                            tooltip: _fullscreen ? 'Exit full screen' : 'Full screen',
                            onPressed: _toggleFullscreen,
                            color: Colors.white,
                            icon: Icon(
                              _fullscreen
                                  ? Icons.fullscreen_exit_rounded
                                  : Icons.fullscreen_rounded,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Icon(
                            _volume == 0
                                ? Icons.volume_off_rounded
                                : Icons.volume_up_rounded,
                            color: Colors.white70,
                            size: AppDimens.iconSmall,
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 2,
                                thumbShape:
                                    const RoundSliderThumbShape(enabledThumbRadius: 5),
                                activeTrackColor: Colors.white70,
                                inactiveTrackColor: Colors.white24,
                                thumbColor: Colors.white,
                              ),
                              child: Slider(
                                value: _volume,
                                onChanged: (v) async {
                                  setState(() => _volume = v);
                                  await controller.setVolume(v);
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: AppDimens.space12),
                          for (final option in _speeds)
                            if (option == 1.0 || option == 1.5 || option == 2.0)
                              Padding(
                                padding: const EdgeInsets.only(right: AppDimens.space4),
                                child: ChoiceChip(
                                  label: Text(option == 1.0 ? '1×' : '$option×'),
                                  selected: (_speed - option).abs() < 0.001,
                                  onSelected: (_) async {
                                    setState(() => _speed = option);
                                    await controller.setPlaybackSpeed(option);
                                  },
                                ),
                              ),
                        ],
                      ),
                      const SizedBox(height: AppDimens.space4),
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
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0x99000000),
          ),
          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 44),
        ),
      ),
    );
  }
}
