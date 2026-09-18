import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_motion.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/models/file_entry.dart';
import '../../../core/utils/format.dart';
import '../../../services/api.dart';
import '../../../services/download_service.dart';
import '../../../services/media_cache.dart';
import '../../widgets/one_ui_empty_state.dart';
import '../../widgets/one_ui_surface.dart';

/// One UI music player.
///
/// ## Large-file behaviour
///
/// Tracks are streamed to a bounded on-disk cache ([MediaCache]) and played by
/// the platform audio backend from a real file. At no point is a whole track
/// held in memory, and the cache evicts least-recently-used entries past its
/// budget. The very first play of a track therefore shows an honest buffering
/// percentage instead of pretending to stream instantly.
///
/// ## Metadata
///
/// NexaDrive does not parse embedded ID3/Vorbis tags (no decoder dependency),
/// so title/artist are derived from the filename and folder, and the artwork
/// block is an intentional NexaDrive tile rather than a claim about the
/// track's real cover.
class AudioPlayerScreen extends StatefulWidget {
  final FileEntry file;
  final Api api;

  /// Sibling audio files, so previous/next navigate a real queue.
  final List<FileEntry> playlist;

  const AudioPlayerScreen({
    super.key,
    required this.file,
    required this.api,
    this.playlist = const [],
  });

  @override
  State<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends State<AudioPlayerScreen> {
  late final AudioPlayer _player = AudioPlayer();
  late List<FileEntry> _queue;
  late int _index;

  final List<StreamSubscription<Object?>> _subscriptions = [];

  MediaCache? _cache;
  File? _localFile;
  double? _loadProgress;
  bool _preparing = true;
  String? _error;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  double _speed = 1.0;
  bool _dragging = false;

  CancelToken? _cancel;

  @override
  void initState() {
    super.initState();
    _queue = widget.playlist.where((e) => !e.isFolder).toList();
    if (_queue.isEmpty) _queue = [widget.file];
    final found = _queue.indexWhere((e) => e.path == widget.file.path);
    if (found < 0) {
      _queue = [widget.file, ..._queue];
      _index = 0;
    } else {
      _index = found;
    }

    _subscriptions.addAll([
      _player.onDurationChanged.listen((d) {
        if (mounted) setState(() => _duration = d);
      }),
      _player.onPositionChanged.listen((p) {
        if (!mounted || _dragging) return;
        setState(() => _position = p);
      }),
      _player.onPlayerStateChanged.listen((s) {
        if (mounted) setState(() => _playing = s == PlayerState.playing);
      }),
      _player.onPlayerComplete.listen((_) {
        if (!mounted) return;
        if (_index + 1 < _queue.length) {
          _openTrack(_index + 1);
        } else {
          setState(() {
            _playing = false;
            _position = Duration.zero;
          });
        }
      }),
    ]);

    _prepare();
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _cancel?.cancel();
    _player.dispose();
    super.dispose();
  }

  FileEntry get _current => _queue[_index];

  /// Fraction of the track -> absolute position. Zero duration means the
  /// backend has not reported a length yet, so the target stays at the start.
  Duration _positionFor(double fraction) => Duration(
        milliseconds:
            (fraction.clamp(0.0, 1.0) * _duration.inMilliseconds).round(),
      );

  String get _namespace => widget.api.session.cacheNamespace;

  String _fingerprint(FileEntry entry) =>
      '${entry.modifiedAt ?? ''}|${entry.size ?? ''}';

  Future<void> _prepare({bool autoplay = true}) async {
    final entry = _current;
    setState(() {
      _preparing = true;
      _error = null;
      _loadProgress = null;
      _localFile = null;
      _position = Duration.zero;
      _duration = Duration.zero;
    });
    _cancel?.cancel();
    final cancel = CancelToken();
    _cancel = cancel;

    try {
      final cache = _cache ??= await MediaCache.open(widget.api);
      final file = await cache.fetch(
        namespace: _namespace,
        remotePath: entry.path,
        fingerprint: _fingerprint(entry),
        cancel: cancel,
        onProgress: (received, total) {
          if (!mounted || total == null || total <= 0) return;
          setState(() => _loadProgress = received / total);
        },
      );
      if (!mounted || cancel.isCancelled) return;
      setState(() {
        _localFile = file;
        _preparing = false;
        _loadProgress = null;
      });
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setSourceDeviceFile(file.path);
      await _player.setPlaybackRate(_speed);
      if (autoplay) await _player.resume();
    } on SaveCancelled {
      // Superseded by another track; the new prepare() owns the state.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _preparing = false;
        _error = _friendly(e);
      });
    }
  }

  String _friendly(Object e) {
    if (e is SaveException) return e.message;
    if (e is ApiException) {
      if (e.status == 401) return 'Your session expired. Sign in again.';
      if (e.status == 404) return 'This track is no longer on the server.';
      return e.message;
    }
    return 'The track could not be prepared for playback.';
  }

  Future<void> _openTrack(int index) async {
    if (index < 0 || index >= _queue.length) return;
    setState(() => _index = index);
    await _prepare();
  }

  Future<void> _togglePlay() async {
    if (_localFile == null) {
      await _prepare();
      return;
    }
    if (_playing) {
      await _player.pause();
    } else {
      if (_position >= _duration && _duration > Duration.zero) {
        await _player.seek(Duration.zero);
      }
      await _player.resume();
    }
  }

  Future<void> _setSpeed(double speed) async {
    setState(() => _speed = speed);
    try {
      await _player.setPlaybackRate(speed);
    } catch (_) {
      // Some platform backends ignore rate changes; the UI value still shows
      // the request rather than silently reverting.
    }
  }

  Future<void> _saveToDevice() async {
    final entry = _current;
    try {
      final result = await DownloadService(widget.api).saveAs(
        remotePath: entry.path,
        fileName: entry.name,
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

  // --------------------------------------------------------------- metadata
  /// `Artist - Title.mp3` -> (Artist, Title); otherwise the folder name is
  /// used as the artist so the header still reads like a music player.
  static (String, String) describe(FileEntry entry) {
    final stem = _stem(entry.name);
    final match = RegExp(r'^(.{1,64}?)\s+[-–]\s+(.+)$').firstMatch(stem);
    if (match != null) {
      final artist = match.group(1)!.trim();
      final title = match.group(2)!.trim();
      if (artist.isNotEmpty && title.isNotEmpty) return (artist, title);
    }
    final segments = entry.path.split('/')..removeLast();
    final folder = segments.isNotEmpty && segments.last.isNotEmpty
        ? segments.last
        : 'NexaDrive';
    return (folder, stem);
  }

  static String _stem(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final entry = _current;
    final (artist, title) = describe(entry);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Now playing'),
        actions: [
          IconButton(
            tooltip: 'Save to device',
            onPressed: _saveToDevice,
            icon: const Icon(Icons.download_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.pageMargin,
            AppDimens.space8,
            AppDimens.pageMargin,
            AppDimens.space24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Artwork(
                seed: entry.name,
                size: MediaQuery.sizeOf(context).width.clamp(200.0, 420.0) - 48,
              ),
              const SizedBox(height: AppDimens.space24),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTextStyle.sectionHeader.copyWith(
                  color: AppColors.textPrimaryFor(brightness),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppDimens.space4),
              Text(
                artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTextStyle.rowSubtitle
                    .copyWith(color: AppColors.textSecondaryFor(brightness)),
              ),
              if (_queue.length > 1) ...[
                const SizedBox(height: AppDimens.space4),
                Text(
                  'Track ${_index + 1} of ${_queue.length}',
                  textAlign: TextAlign.center,
                  style: AppTextStyle.micro
                      .copyWith(color: AppColors.textTertiaryFor(brightness)),
                ),
              ],
              const SizedBox(height: AppDimens.space20),
              if (_error != null)
                OneUiEmptyState(
                  icon: Icons.music_off_rounded,
                  title: 'Can\u2019t play this track',
                  hint: _error,
                  actionLabel: 'Retry',
                  onAction: () => _prepare(),
                )
              else if (_preparing)
                _Buffering(progress: _loadProgress, title: title)
              else
                _Controls(
                  playing: _playing,
                  position: _position,
                  duration: _duration,
                  speed: _speed,
                  canPrevious: _index > 0,
                  canNext: _index + 1 < _queue.length,
                  onToggle: _togglePlay,
                  onPrevious: () => _openTrack(_index - 1),
                  onNext: () => _openTrack(_index + 1),
                  onSpeed: _setSpeed,
                  onDragStart: () => setState(() => _dragging = true),
                  // Track the thumb live: the elapsed-time label is driven by
                  // `_position`, so ignoring this leaves the label frozen while
                  // the user scrubs.
                  onDragChanged: (v) => setState(
                    () => _position = _positionFor(v),
                  ),
                  onDragEnd: (v) async {
                    setState(() => _dragging = false);
                    setState(() => _position = _positionFor(v));
                    await _player.seek(_positionFor(v));
                  },
                ),
              if (_queue.length > 1) ...[
                const SizedBox(height: AppDimens.space24),
                Row(
                  children: [
                    const Icon(Icons.queue_music_rounded,
                        size: AppDimens.iconSmall),
                    const SizedBox(width: AppDimens.space8),
                    Text(
                      'Queue in this folder',
                      style: AppTextStyle.sectionHeader.copyWith(
                        color: AppColors.textPrimaryFor(brightness),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppDimens.space8),
                OneUiSurface(
                  level: OneUiSurfaceLevel.surface,
                  radius: AppDimens.radiusCard,
                  child: Column(
                    children: [
                      for (var i = 0; i < _queue.length; i++)
                        ListTile(
                          selected: i == _index,
                          selectedTileColor:
                              AppColors.accentContainerFor(brightness),
                          leading: Icon(
                            i == _index && _playing
                                ? Icons.graphic_eq_rounded
                                : Icons.music_note_rounded,
                            color: i == _index
                                ? AppColors.accentTextFor(brightness)
                                : AppColors.textTertiaryFor(brightness),
                          ),
                          title: Text(
                            describe(_queue[i]).$2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyle.rowTitle.copyWith(
                              color: AppColors.textPrimaryFor(brightness),
                            ),
                          ),
                          subtitle: Text(
                            Format.bytes(_queue[i].size),
                            style: AppTextStyle.caption.copyWith(
                              color: AppColors.textSecondaryFor(brightness),
                            ),
                          ),
                          onTap: () => _openTrack(i),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Decorative, deterministic artwork tile. Deliberately not presented as the
/// track's real cover art.
class _Artwork extends StatelessWidget {
  final String seed;
  final double size;
  const _Artwork({required this.seed, required this.size});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final hue = (seed.hashCode.abs() % 360).toDouble();
    final base = HSLColor.fromAHSL(
            1, hue, 0.32, brightness == Brightness.dark ? 0.24 : 0.86)
        .toColor();
    final accent = HSLColor.fromAHSL(1, (hue + 28) % 360, 0.42,
            brightness == Brightness.dark ? 0.34 : 0.74)
        .toColor();

    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppDimens.radiusHero),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [base, accent],
          ),
        ),
        child: Center(
          child: Icon(
            Icons.album_rounded,
            size: size * 0.34,
            color: AppColors.textPrimaryFor(brightness).withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }
}

/// Honest buffering state: shows real byte progress when the server reported a
/// content length, and an indeterminate spinner when it did not.
class _Buffering extends StatelessWidget {
  final double? progress;
  final String title;
  const _Buffering({required this.progress, required this.title});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final percent = progress == null ? null : (progress! * 100).round();
    return Column(
      children: [
        SizedBox(
          height: 52,
          child: Center(
            child: percent == null
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    '$percent%',
                    style: AppTextStyle.metricValue.copyWith(
                      color: AppColors.textPrimaryFor(brightness),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: AppDimens.space12),
        if (progress != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppDimens.space24),
            child: LinearProgressIndicator(value: progress),
          ),
        const SizedBox(height: AppDimens.space12),
        Text(
          'Preparing “$title” for playback…',
          textAlign: TextAlign.center,
          style: AppTextStyle.caption
              .copyWith(color: AppColors.textSecondaryFor(brightness)),
        ),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  final bool playing;
  final Duration position;
  final Duration duration;
  final double speed;
  final bool canPrevious;
  final bool canNext;
  final Future<void> Function() onToggle;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<double> onSpeed;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragChanged;
  final ValueChanged<double> onDragEnd;

  const _Controls({
    required this.playing,
    required this.position,
    required this.duration,
    required this.speed,
    required this.canPrevious,
    required this.canNext,
    required this.onToggle,
    required this.onPrevious,
    required this.onNext,
    required this.onSpeed,
    required this.onDragStart,
    required this.onDragChanged,
    required this.onDragEnd,
  });

  static const _speeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final total = duration.inMilliseconds;
    final value = total > 0
        ? (position.inMilliseconds / total).clamp(0.0, 1.0).toDouble()
        : 0.0;

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: Slider(
            value: value,
            onChangeStart: (_) => onDragStart(),
            onChanged: onDragChanged,
            onChangeEnd: onDragEnd,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppDimens.space4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                Format.duration(position),
                style: AppTextStyle.micro
                    .copyWith(color: AppColors.textSecondaryFor(brightness)),
              ),
              Text(
                total > 0 ? Format.duration(duration) : '--:--',
                style: AppTextStyle.micro
                    .copyWith(color: AppColors.textSecondaryFor(brightness)),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppDimens.space12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Previous track',
              onPressed: canPrevious ? onPrevious : null,
              iconSize: 34,
              icon: const Icon(Icons.skip_previous_rounded),
            ),
            const SizedBox(width: AppDimens.space8),
            _PlayButton(playing: playing, onPressed: onToggle),
            const SizedBox(width: AppDimens.space8),
            IconButton(
              tooltip: 'Next track',
              onPressed: canNext ? onNext : null,
              iconSize: 34,
              icon: const Icon(Icons.skip_next_rounded),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.space16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppDimens.space8,
          children: [
            for (final option in _speeds)
              ChoiceChip(
                label: Text(option == 1.0 ? '1×' : '$option×'),
                selected: (speed - option).abs() < 0.001,
                onSelected: (_) => onSpeed(option),
              ),
          ],
        ),
      ],
    );
  }
}

class _PlayButton extends StatelessWidget {
  final bool playing;
  final Future<void> Function() onPressed;
  const _PlayButton({required this.playing, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Semantics(
      button: true,
      label: playing ? 'Pause' : 'Play',
      child: SizedBox(
        width: 72,
        height: 72,
        child: FilledButton(
          style: FilledButton.styleFrom(
            shape: const CircleBorder(),
            padding: EdgeInsets.zero,
            backgroundColor: AppColors.accentFor(brightness),
          ),
          onPressed: onPressed,
          child: AnimatedSwitcher(
            duration: AppMotion.resolve(context, AppMotion.fast),
            switchInCurve: AppMotion.enter,
            switchOutCurve: AppMotion.exit,
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              key: ValueKey(playing),
              size: 38,
            ),
          ),
        ),
      ),
    );
  }
}
