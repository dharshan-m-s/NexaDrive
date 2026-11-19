import 'dart:async';
import 'dart:ui' as ui;

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
import '../../../services/media_proxy.dart';
import '../../widgets/nexa_components.dart';

/// Immersive music player with floating, tonal controls.
///
/// ## Large-file behaviour
///
/// Tracks are streamed from the server through a loopback-only proxy
/// ([MediaProxy]) that attaches the session token. The platform audio backend
/// sees an HTTP URL and can seek with range requests, while no track bytes are
/// written to the device: the server remains the only place media is stored.
///
/// ## Metadata
///
/// NexaDrive does not parse embedded ID3/Vorbis tags (no decoder dependency),
/// so title/artist are derived from the filename and folder. The circular
/// artwork is an intentional abstract anchor, not a claim about embedded cover
/// art.
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

  MediaProxy? _proxy;
  bool _ready = false;
  bool _preparing = true;
  String? _error;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  double _speed = 1.0;
  bool _dragging = false;

  CancelToken? _cancel;

  static const _speeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

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
    unawaited(_proxy?.close());
    super.dispose();
  }

  FileEntry get _current => _queue[_index];

  /// Fraction of the track -> absolute position. Zero duration means the
  /// backend has not reported a length yet, so the target stays at the start.
  Duration _positionFor(double fraction) => Duration(
        milliseconds:
            (fraction.clamp(0.0, 1.0) * _duration.inMilliseconds).round(),
      );

  Future<void> _prepare({bool autoplay = true}) async {
    final entry = _current;
    setState(() {
      _preparing = true;
      _error = null;
      _ready = false;
      _position = Duration.zero;
      _duration = Duration.zero;
    });
    _cancel?.cancel();
    final cancel = CancelToken();
    _cancel = cancel;

    try {
      final proxy = _proxy ??= await MediaProxy.start(widget.api);
      if (!mounted) {
        if (identical(_proxy, proxy)) _proxy = null;
        await proxy.close();
        return;
      }
      if (cancel.isCancelled) return;
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setSourceUrl(proxy.urlFor(entry.path));
      await _player.setPlaybackRate(_speed);
      if (!mounted || cancel.isCancelled) return;
      setState(() {
        _ready = true;
        _preparing = false;
      });
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
    if (!_ready) {
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
    // A player is a focused media surface, not a settings page. Keep the same
    // dark, token-backed treatment as the photo and video viewers so controls
    // float over the music instead of sitting in cards and divided rows.
    final darkTheme = Theme.of(context).copyWith(
      brightness: Brightness.dark,
      colorScheme: AppColors.scheme(Brightness.dark),
    );
    final scheme = darkTheme.colorScheme;
    final entry = _current;
    final (artist, title) = describe(entry);

    return Scaffold(
      backgroundColor: AppColors.canvasDark,
      body: Theme(
        data: darkTheme,
        child: Stack(
          children: [
            Positioned.fill(child: _AmbientArt(seed: entry.name)),
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.space8,
                      vertical: AppDimens.space8,
                    ),
                    child: Row(
                      children: [
                        _FloatingIcon(
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
                                'Now playing',
                                textAlign: TextAlign.center,
                                style: AppTextStyle.labelMedium.copyWith(
                                  color: scheme.onSurface,
                                ),
                              ),
                              if (_queue.length > 1)
                                Text(
                                  'Track ${_index + 1} of ${_queue.length}',
                                  style: AppTextStyle.caption.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Material(
                          color: scheme.surfaceContainerHigh,
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: PopupMenuButton<_AudioTopAction>(
                            tooltip: 'More actions',
                            color: scheme.surfaceContainerHigh,
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
                                case _AudioTopAction.save:
                                  _saveToDevice();
                                case _AudioTopAction.speed05:
                                  _setSpeed(0.5);
                                case _AudioTopAction.speed075:
                                  _setSpeed(0.75);
                                case _AudioTopAction.speed1:
                                  _setSpeed(1.0);
                                case _AudioTopAction.speed125:
                                  _setSpeed(1.25);
                                case _AudioTopAction.speed15:
                                  _setSpeed(1.5);
                                case _AudioTopAction.speed2:
                                  _setSpeed(2.0);
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: _AudioTopAction.save,
                                child: Text('Save to device'),
                              ),
                              const PopupMenuDivider(),
                              for (final option in _speeds)
                                PopupMenuItem<_AudioTopAction>(
                                  value: switch (option) {
                                    0.5 => _AudioTopAction.speed05,
                                    0.75 => _AudioTopAction.speed075,
                                    1.0 => _AudioTopAction.speed1,
                                    1.25 => _AudioTopAction.speed125,
                                    1.5 => _AudioTopAction.speed15,
                                    _ => _AudioTopAction.speed2,
                                  },
                                  child: Row(
                                    children: [
                                      Text(
                                        option == 1.0
                                            ? '1× speed'
                                            : '$option× speed',
                                      ),
                                      if ((_speed - option).abs() < 0.001)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            left: AppDimens.space8,
                                          ),
                                          child: Icon(
                                            Icons.check_rounded,
                                            size: AppDimens.iconSmall,
                                            color: scheme.primary,
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
                  Expanded(
                    child: Center(
                      child: _error != null
                          ? Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppDimens.pageMargin,
                              ),
                              child: NexaEmptyState(
                                icon: Icons.music_off_rounded,
                                title: 'Can\u2019t play this track',
                                hint: _error,
                                actionLabel: 'Retry',
                                onAction: () => _prepare(),
                              ),
                            )
                          : _preparing
                              ? _Buffering(title: title)
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _Artwork(
                                      seed: entry.name,
                                      size: MediaQuery.sizeOf(context)
                                          .width
                                          .clamp(220.0, 340.0),
                                    ),
                                    const SizedBox(height: AppDimens.space32),
                                    Text(
                                      title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: AppTextStyle.title1.copyWith(
                                        color: scheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: AppDimens.space4),
                                    Text(
                                      artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTextStyle.rowSubtitle.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                    ),
                  ),
                  if (_queue.length > 1)
                    _QueueStrip(
                      queue: _queue,
                      current: _index,
                      onTap: _openTrack,
                    ),
                  if (!_preparing && _error == null)
                    _Controls(
                      playing: _playing,
                      position: _position,
                      duration: _duration,
                      canPrevious: _index > 0,
                      canNext: _index + 1 < _queue.length,
                      onToggle: _togglePlay,
                      onPrevious: () => _openTrack(_index - 1),
                      onNext: () => _openTrack(_index + 1),
                      onDragStart: () => setState(() => _dragging = true),
                      onDragChanged: (v) =>
                          setState(() => _position = _positionFor(v)),
                      onDragEnd: (v) async {
                        setState(() => _dragging = false);
                        setState(() => _position = _positionFor(v));
                        await _player.seek(_positionFor(v));
                      },
                    )
                  else
                    const SizedBox(height: AppDimens.space24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _AudioTopAction {
  save,
  speed05,
  speed075,
  speed1,
  speed125,
  speed15,
  speed2
}

/// Faint, out-of-focus tonal shapes. They give the player depth without a
/// banner, card, or a glass material that would compete with the track.
class _AmbientArt extends StatelessWidget {
  final String seed;
  const _AmbientArt({required this.seed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = [
      scheme.primary,
      scheme.secondary,
      scheme.tertiary,
    ][seed.hashCode.abs() % 3];
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            left: -(AppDimens.space56 + AppDimens.space40),
            top: MediaQuery.sizeOf(context).height * 0.12,
            child: _softCircle(
              AppDimens.space56 * 5 + AppDimens.space8,
              tone.withValues(alpha: 0.10),
            ),
          ),
          Positioned(
            right: -(AppDimens.space56 + AppDimens.space8),
            bottom: MediaQuery.sizeOf(context).height * 0.22,
            child: _softCircle(
              AppDimens.space56 * 4,
              tone.withValues(alpha: 0.07),
            ),
          ),
        ],
      ),
    );
  }

  Widget _softCircle(double size, Color color) {
    return ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

/// Deterministic circular artwork. There is no outer tile or badge: this is a
/// visual anchor, not a claim about embedded cover art.
class _Artwork extends StatelessWidget {
  final String seed;
  final double size;
  const _Artwork({required this.seed, required this.size});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = [
      scheme.primary,
      scheme.secondary,
      scheme.tertiary,
    ][seed.hashCode.abs() % 3];

    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest.withValues(alpha: 0.55),
            shape: BoxShape.circle,
            border: Border.all(
              color: accent.withValues(alpha: 0.38),
              width: AppDimens.space2,
            ),
          ),
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: SizedBox(
                width: size * 0.58,
                height: size * 0.58,
                child: Icon(
                  Icons.graphic_eq_rounded,
                  size: AppDimens.iconHero,
                  color: accent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Connecting state while the platform backend opens the stream.
class _Buffering extends StatelessWidget {
  final String title;
  const _Buffering({required this.title});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        SizedBox(
          height: AppDimens.touchTargetLarge,
          child: Center(
            child: SizedBox(
              width: AppDimens.iconSmall,
              height: AppDimens.iconSmall,
              child: CircularProgressIndicator(strokeWidth: AppDimens.space2),
            ),
          ),
        ),
        const SizedBox(height: AppDimens.space12),
        Text(
          'Connecting to \u201c$title\u201d\u2026',
          textAlign: TextAlign.center,
          style:
              AppTextStyle.bodySmall.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// A quiet queue strip: labels float on the canvas instead of a grouped card.
class _QueueStrip extends StatelessWidget {
  final List<FileEntry> queue;
  final int current;
  final ValueChanged<int> onTap;

  const _QueueStrip({
    required this.queue,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimens.space8),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.pageMargin,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Queue in this folder',
                style: AppTextStyle.labelSmall.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppDimens.space6),
          SizedBox(
            height: AppDimens.space48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.pageMargin,
              ),
              itemCount: queue.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: AppDimens.space16),
              itemBuilder: (context, index) {
                final selected = index == current;
                final label = _AudioPlayerScreenState.describe(queue[index]).$2;
                return Semantics(
                  button: true,
                  selected: selected,
                  label: label,
                  child: InkWell(
                    onTap: () => onTap(index),
                    borderRadius: BorderRadius.circular(AppDimens.radiusSmall),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimens.space4,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: AppDimens.space6,
                            height: AppDimens.space6,
                            decoration: BoxDecoration(
                              color: selected
                                  ? scheme.primary
                                  : Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(height: AppDimens.space6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 132),
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.caption.copyWith(
                                color: selected
                                    ? scheme.onSurface
                                    : scheme.onSurfaceVariant,
                              ),
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
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  final bool playing;
  final Duration position;
  final Duration duration;
  final bool canPrevious;
  final bool canNext;
  final Future<void> Function() onToggle;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragChanged;
  final ValueChanged<double> onDragEnd;

  const _Controls({
    required this.playing,
    required this.position,
    required this.duration,
    required this.canPrevious,
    required this.canNext,
    required this.onToggle,
    required this.onPrevious,
    required this.onNext,
    required this.onDragStart,
    required this.onDragChanged,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = duration.inMilliseconds;
    final value = total > 0
        ? (position.inMilliseconds / total).clamp(0.0, 1.0).toDouble()
        : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.space16,
        AppDimens.space8,
        AppDimens.space16,
        AppDimens.space24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: scheme.onSurface,
              inactiveTrackColor: scheme.onSurface.withValues(alpha: 0.24),
              thumbColor: scheme.onSurface,
              overlayColor: scheme.onSurface.withValues(alpha: 0.16),
              trackHeight: AppDimens.space2,
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: AppDimens.space4,
              ),
              overlayShape: const RoundSliderOverlayShape(
                overlayRadius: AppDimens.space12,
              ),
            ),
            child: Semantics(
              label: 'Playback position',
              child: Slider(
                value: value,
                onChangeStart: (_) => onDragStart(),
                onChanged: onDragChanged,
                onChangeEnd: onDragEnd,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppDimens.space4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  Format.duration(position),
                  style:
                      AppTextStyle.labelSmall.copyWith(color: scheme.onSurface),
                ),
                Text(
                  total > 0 ? Format.duration(duration) : '--:--',
                  style: AppTextStyle.labelSmall
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimens.space12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _FloatingIcon(
                icon: Icons.skip_previous_rounded,
                tooltip: 'Previous track',
                onTap: canPrevious ? onPrevious : null,
              ),
              const SizedBox(width: AppDimens.space32),
              _PlayButton(playing: playing, onPressed: onToggle),
              const SizedBox(width: AppDimens.space32),
              _FloatingIcon(
                icon: Icons.skip_next_rounded,
                tooltip: 'Next track',
                onTap: canNext ? onNext : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FloatingIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const _FloatingIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: tooltip,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        color: scheme.onSurface,
        iconSize: AppDimens.iconLarge,
        icon: Icon(icon),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final bool playing;
  final Future<void> Function() onPressed;
  const _PlayButton({required this.playing, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: playing ? 'Pause' : 'Play',
      child: SizedBox(
        width: AppDimens.iconHero,
        height: AppDimens.iconHero,
        child: FilledButton(
          style: FilledButton.styleFrom(
            shape: const CircleBorder(),
            padding: EdgeInsets.zero,
            minimumSize: const Size(
              AppDimens.iconHero,
              AppDimens.iconHero,
            ),
          ),
          onPressed: onPressed,
          child: AnimatedSwitcher(
            duration: AppMotion.resolve(context, AppMotion.fast),
            switchInCurve: AppMotion.curveFor(context, AppMotion.enter),
            switchOutCurve: AppMotion.curveFor(context, AppMotion.exit),
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              key: ValueKey(playing),
              size: AppDimens.iconTile,
            ),
          ),
        ),
      ),
    );
  }
}
