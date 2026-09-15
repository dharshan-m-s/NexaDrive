import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/models/file_entry.dart';
import '../../../core/utils/format.dart';
import '../../../services/api.dart';

/// One UI audio player — streams a file from the server into a temp file
/// then plays it in-app using audioplayers.
class AudioViewerScreen extends StatefulWidget {
  final FileEntry file;
  final Api api;
  const AudioViewerScreen({super.key, required this.file, required this.api});

  @override
  State<AudioViewerScreen> createState() => _AudioViewerScreenState();
}

class _AudioViewerScreenState extends State<AudioViewerScreen> {
  AudioPlayer? _player;
  bool _loading = true;
  bool _playing = false;
  bool _busy = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() => _loading = true);
    try {
      final dir = await getTemporaryDirectory();
      final outPath = '${dir.path}/${widget.file.name}';
      await widget.api.downloadToFile(widget.file.path, outPath);
      if (!mounted) return;
      final player = AudioPlayer();
      _player = player;
      player.onPlayerStateChanged.listen((s) {
        if (!mounted) return;
        setState(() => _playing = s == PlayerState.playing);
      });
      player.onPositionChanged.listen((d) {
        if (!mounted) return;
        setState(() => _position = d);
      });
      player.onDurationChanged.listen((d) {
        if (!mounted) return;
        setState(() => _duration = d);
      });
      await player.play(DeviceFileSource(outPath));
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    final player = _player;
    if (player == null) return;
    if (_playing) {
      await player.pause();
    } else {
      await player.resume();
    }
  }

  Future<void> _seek(Duration offset) async {
    final player = _player;
    if (player == null) return;
    final target = _position + offset;
    await player.seek(
      target < Duration.zero
          ? Duration.zero
          : target > _duration
              ? _duration
              : target,
    );
  }

  Future<void> _download() async {
    final player = _player;
    if (player == null || _busy) return;
    setState(() => _busy = true);
    try {
      // Save to the platform's downloads directory (fallback: temp) so the
      // file lands somewhere the user can actually reach — never a hard-coded
      // /tmp path that only exists on Linux.
      final dir = await getDownloadsDirectory() ?? await getTemporaryDirectory();
      final outPath = '${dir.path}/${widget.file.name}';
      await widget.api.downloadToFile(widget.file.path, outPath);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(content: Text('${widget.file.name} saved')),
          );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final accent = AppColors.accentFor(brightness);
    final onSurface = AppColors.textPrimaryFor(brightness);
    final secondary = AppColors.textSecondaryFor(brightness);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Download',
            onPressed: _busy ? null : _download,
            icon: Icon(Icons.download_outlined, color: accent),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : _error != null
                ? Padding(
                    padding: const EdgeInsets.all(AppDimens.pageMargin),
                    child: Column(
                      children: [
                        const Spacer(),
                        const Icon(Icons.error_outline_rounded, size: 56, color: AppColors.errorLight),
                        const SizedBox(height: AppDimens.space16),
                        Text(
                          'Couldn\'t load this audio file',
                          style: AppTextStyle.sectionHeader.copyWith(color: onSurface),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppDimens.space8),
                        Text(
                          _error!,
                          style: AppTextStyle.caption.copyWith(color: secondary),
                          textAlign: TextAlign.center,
                        ),
                        const Spacer(),
                      ],
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppDimens.pageMargin),
                    child: Column(
                      children: [
                        const Spacer(flex: 2),
                        Container(
                          width: 128,
                          height: 128,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(AppDimens.radiusCard),
                          ),
                          child: Icon(Icons.music_note_rounded, size: 60, color: accent),
                        ),
                        const SizedBox(height: AppDimens.space24),
                        Text(
                          widget.file.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: AppTextStyle.sectionHeader.copyWith(
                            color: onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(flex: 2),
                        SliderTheme(
                          data: SliderThemeData(
                            thumbColor: accent,
                            activeTrackColor: accent,
                            inactiveTrackColor: accent.withValues(alpha: 0.18),
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                          ),
                          child: Slider(
                            value: _duration.inMilliseconds > 0
                                ? _position.inMilliseconds / _duration.inMilliseconds
                                : 0.0,
                            onChanged: (value) {
                              _player?.seek(Duration(
                                milliseconds: (value * _duration.inMilliseconds).round(),
                              ));
                            },
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              Format.duration(_position),
                              style: AppTextStyle.caption.copyWith(color: secondary),
                            ),
                            Text(
                              Format.duration(_duration),
                              style: AppTextStyle.caption.copyWith(color: secondary),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppDimens.space16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _CircleButton(
                              icon: Icons.replay_10_rounded,
                              onTap: () => _seek(const Duration(seconds: -10)),
                            ),
                            const SizedBox(width: AppDimens.space24),
                            _PlayButton(playing: _playing, onTap: _togglePlay),
                            const SizedBox(width: AppDimens.space24),
                            _CircleButton(
                              icon: Icons.forward_10_rounded,
                              onTap: () => _seek(const Duration(seconds: 10)),
                            ),
                          ],
                        ),
                        const Spacer(flex: 3),
                      ],
                    ),
                  ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final bool playing;
  final VoidCallback onTap;
  const _PlayButton({required this.playing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final accent = AppColors.accentFor(brightness);
    return Semantics(
      button: true,
      label: playing ? 'Pause' : 'Play',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: Colors.white,
            size: 36,
          ),
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final bgColor = brightness == Brightness.dark ? AppColors.surfaceAltDark : AppColors.surfaceAltLight;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: bgColor,
          ),
          child: Icon(icon, size: 22, color: AppColors.textPrimaryFor(brightness)),
        ),
      ),
    );
  }
}