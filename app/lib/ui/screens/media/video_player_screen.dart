import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/models/file_entry.dart';
import '../../../core/utils/format.dart';
import '../../../services/api.dart';
import '../../widgets/download_to_view.dart';
import '../../widgets/one_ui_empty_state.dart';

/// One UI video player — streams the clip from the server and plays it in-app
/// via the platform media backend. On platforms without media support (Linux
/// desktop) it degrades to a download-and-open flow.
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
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final controller = VideoPlayerController.networkUrl(
        widget.api.fileDownloadUri(widget.file.path),
        httpHeaders: widget.api.authHeaders,
      );
      _controller = controller;
      await controller.initialize();
      await controller.play();
      if (!mounted) return;
      controller.addListener(_onListen);
      setState(() => _initializing = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _initializing = false;
      });
    }
  }

  void _onListen() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _controller?.removeListener(_onListen);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final value = controller?.value;
    final initialized = value?.isInitialized == true;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (initialized || _error != null)
            IconButton(
              tooltip: 'Download',
              onPressed: () => _fallback(),
              icon: const Icon(Icons.download_outlined, color: Colors.white),
            ),
        ],
      ),
      body: SafeArea(
        child: _initializing
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : _error != null
                ? OneUiEmptyState(
                    icon: Icons.movie_outlined,
                    title: 'Can\'t play this video here',
                    hint: _error,
                    actionLabel: 'Download instead',
                    onAction: _fallback,
                  )
                : _buildPlayer(controller!, value!),
      ),
    );
  }

  Widget _buildPlayer(VideoPlayerController controller, VideoPlayerValue value) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: value.aspectRatio > 0
                  ? value.aspectRatio
                  : 16 / 9,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  VideoPlayer(controller),
                  if (!value.isPlaying)
                    _PlayOverlay(onTap: () {
                      controller.value.isPlaying ? controller.pause() : controller.play();
                    }),
                ],
              ),
            ),
          ),
        ),
        _VideoControls(
          value: value,
          onPlayPause: () {
            value.isPlaying ? controller.pause() : controller.play();
          },
          onSeek: (d) => controller.seekTo(d),
        ),
        const SizedBox(height: AppDimens.space8),
      ],
    );
  }

  void _fallback() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DownloadToViewScreen(
          file: widget.file,
          icon: Icons.movie_rounded,
          subtitle: 'Download the video to play it with your device player.',
          downloader: widget.api.downloadToFile,
        ),
      ),
    );
  }
}

class _PlayOverlay extends StatelessWidget {
  final VoidCallback onTap;
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

class _VideoControls extends StatelessWidget {
  final VideoPlayerValue value;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  const _VideoControls({
    required this.value,
    required this.onPlayPause,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    final duration = value.duration;
    final position = value.position;
    final fraction = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.space16, AppDimens.space8, AppDimens.space16, 0,
      ),
      child: Row(
        children: [
          IconButton(
            color: Colors.white,
            tooltip: value.isPlaying ? 'Pause' : 'Play',
            onPressed: onPlayPause,
            iconSize: 34,
            icon: Icon(
              value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            ),
          ),
          Text(
            Format.duration(position),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Expanded(
            child: SliderTheme(
              data: const SliderThemeData(
                thumbColor: AppColors.accentDark,
                activeTrackColor: AppColors.accentDark,
                inactiveTrackColor: Colors.white24,
                trackHeight: 3,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: fraction,
                onChanged: (v) {
                  final target = Duration(
                    milliseconds: (v * duration.inMilliseconds).round(),
                  );
                  onSeek(target);
                },
              ),
            ),
          ),
          Text(
            Format.duration(duration),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}