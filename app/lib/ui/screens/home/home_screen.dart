import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_dimensions.dart';
import '../../../../core/design/app_typography.dart';
import '../../../../core/models/file_entry.dart';
import '../../../../core/utils/file_kind.dart';
import '../../../../core/utils/format.dart';
import '../../../services/api.dart';
import '../../../services/image_pipeline.dart';
import '../../../services/session.dart';
import '../../../services/upload_manager.dart';
import '../../navigation/file_opener.dart';
import '../../widgets/nexa_components.dart';
import '../files/files_screen.dart' show FilesIntent;
import '../transfers/transfers_screen.dart';
import 'storage_insights_screen.dart';

class HomeScreen extends StatefulWidget {
  final Session session;
  final Api api;
  final ValueChanged<int> onNavigate;

  /// Opens My files and asks it to start an action, so "Upload" and
  /// "New folder" do what they say.
  final ValueChanged<FilesIntent>? onFilesIntent;

  const HomeScreen({
    super.key,
    required this.session,
    required this.api,
    required this.onNavigate,
    this.onFilesIntent,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StorageInfo? _storage;
  bool _loading = true;
  String? _error;
  int _pendingUploads = 0;
  List<FileEntry> _recent = const [];
  List<FileEntry> _photos = const [];
  List<Map<String, dynamic>> _shared = const [];
  final Set<String> _failedPhotoThumbs = <String>{};
  final Set<String> _loadingPhotoThumbs = <String>{};

  /// Thumbnail cache for the small photo strip on Home.
  late final ImageRepository _images;

  /// The upload queue this screen shows.
  late final UploadManager _manager;

  @override
  void initState() {
    super.initState();
    _manager = UploadManager.current;
    _images = ImageRepository(widget.api);
    _manager.addListener(_onQueueChanged);
    load();
  }

  @override
  void dispose() {
    _manager.removeListener(_onQueueChanged);
    super.dispose();
  }

  /// Keeps the "waiting to upload" pod in step with the queue.
  void _onQueueChanged() {
    if (!mounted) return;
    final pending = _manager.pendingCount;
    if (pending == _pendingUploads) return;
    setState(() => _pendingUploads = pending);
  }

  Future<void> load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object>([
        widget.api.storage(),
        _readQueue(),
        _readRecent(),
        _readPhotos(),
        _readShared(),
      ]);
      if (!mounted) return;
      setState(() {
        _storage = StorageInfo.fromJson(results[0] as Map<String, dynamic>);
        _pendingUploads = results[1] as int;
        _recent = (results[2] as List<FileEntry>);
        _photos = (results[3] as List<FileEntry>);
        _shared = (results[4] as List<Map<String, dynamic>>);
        _loading = false;
      });
      for (final entry in _photos.take(8)) {
        unawaited(_ensurePhotoThumb(entry));
      }
    } catch (e) {
      if (!mounted) return;
      // A failed load must say so. Silently clearing the spinner leaves the
      // hero area blank, which reads as a broken screen rather than an error.
      setState(() {
        _error = e is ApiException
            ? e.message
            : 'Your storage details could not be loaded.';
        _loading = false;
      });
    }
  }

  Future<int> _readQueue() async => _manager.pendingCount;

  /// Sharing is optional Home context. A failed shared listing must never
  /// blank the page.
  Future<List<Map<String, dynamic>>> _readShared() async {
    try {
      return await widget.api.shared();
    } catch (_) {
      return const [];
    }
  }

  Future<List<FileEntry>> _readRecent() async {
    // The API root is '' — the server rejects '/' as an absolute path.
    final raw = await widget.api.listFiles('');
    // Keep only the five newest as we scan, rather than materializing a
    // FileEntry for every file in the root and sorting the whole list. On a
    // large root that avoids a transient spike the user would never see.
    final recent = <FileEntry>[];
    for (final json in raw) {
      final entry = FileEntry.fromJson(json);
      final modified = entry.modified;
      if (entry.isFolder || modified == null) continue;
      if (recent.length < 5) {
        recent.add(entry);
        recent.sort(_newestFirst);
      } else if (modified.isAfter(recent.last.modified!)) {
        recent[recent.length - 1] = entry;
        recent.sort(_newestFirst);
      }
    }
    return recent;
  }

  static int _newestFirst(FileEntry a, FileEntry b) =>
      b.modified!.compareTo(a.modified!);

  Future<List<FileEntry>> _readPhotos() async {
    try {
      // Use the same authoritative gallery endpoint as the Photos tab rather
      // than assuming every server keeps images in a folder named "Photos".
      final raw = await widget.api.photos();
      final photos = <FileEntry>[];
      for (final json in raw) {
        final entry =
            FileEntry.fromJson(<String, dynamic>{...json, 'type': 'file'});
        if (entry.category == Category.image ||
            entry.category == Category.video) {
          photos.add(entry);
        }
        if (photos.length == 8) break;
      }
      return photos;
    } catch (_) {
      // Home still works when the photo library is unavailable.
      return const [];
    }
  }

  ImageKey _photoKey(FileEntry entry) => ImageRepository.keyFor(
        entry.toJson(),
        namespace: widget.api.session.cacheNamespace,
        rendition: ImageRendition.thumbnail,
      );

  Future<void> _ensurePhotoThumb(FileEntry entry) async {
    if (_failedPhotoThumbs.contains(entry.path) ||
        _loadingPhotoThumbs.contains(entry.path)) {
      return;
    }
    final key = _photoKey(entry);
    if (_images.peekThumbnail(key) != null) return;
    _loadingPhotoThumbs.add(entry.path);
    try {
      await _images.thumbnail(key);
      if (mounted) setState(() {});
    } on ThumbnailUnavailable {
      if (mounted) setState(() => _failedPhotoThumbs.add(entry.path));
    } catch (_) {
    } finally {
      _loadingPhotoThumbs.remove(entry.path);
    }
  }

  Uint8List? _photoThumb(FileEntry entry) {
    if (_failedPhotoThumbs.contains(entry.path)) return null;
    return _images.peekThumbnail(_photoKey(entry));
  }

  /// A stable identity for whichever summary state is showing.
  String get _summaryState {
    if (_storage != null) return 'ready';
    return _loading ? 'loading' : 'error';
  }

  @override
  Widget build(BuildContext context) {
    final storage = _storage;
    final now = DateTime.now();
    final colorScheme = Theme.of(context).colorScheme;
    final continueFile = _recent.isNotEmpty ? _recent.first : null;
    final continuePhoto =
        continueFile == null && _photos.isNotEmpty ? _photos.first : null;
    final continueEntry = continueFile ?? continuePhoto;
    final isPhoto = continuePhoto != null;

    return NexaPage(
      title: 'Home',
      subtitle: 'Your private cloud, at a glance',
      bottomSafeArea: false,
      scrollable: true,
      headerAction: IconButton(
        tooltip: 'Refresh overview',
        onPressed: _loading ? null : load,
        icon: Icon(Icons.refresh_rounded, color: colorScheme.primary),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppDimens.space8),
          _EditorialHeader(now: now),
          const SizedBox(height: AppDimens.space32),

          // ------------------------------- continue where you left off
          _ContinueSection(
            entry: continueEntry,
            isPhoto: isPhoto,
            siblings: isPhoto ? _photos : _recent,
            thumbnailFor: _photoThumb,
            api: widget.api,
            pendingUploads: _pendingUploads,
            onUpload: () => widget.onFilesIntent != null
                ? widget.onFilesIntent!(FilesIntent.upload)
                : widget.onNavigate(1),
            onBrowse: () => widget.onNavigate(1),
            onPhotos: () => widget.onNavigate(3),
            onTransfers: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TransfersScreen()),
              );
            },
          ),
          const SizedBox(height: AppDimens.space32),

          // -------------------------------- storage, as a quiet stat
          NexaStateSwitcher(
            stateKey: ValueKey(_summaryState),
            child: storage != null
                ? _StorageSummary(
                    storage: storage,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => StorageInsightsScreen(api: widget.api),
                      ),
                    ),
                  )
                : _loading
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.only(top: AppDimens.space16),
                          child: NexaCircularProgress(
                            size: AppDimens.iconMedium,
                          ),
                        ),
                      )
                    : _HomeConnectionNotice(
                        message:
                            _error ?? 'Check your connection and try again.',
                        onRetry: load,
                      ),
          ),
          const SizedBox(height: AppDimens.space32),

          // ------------------------------------- quick actions, compact
          const _SectionHeader('Quick actions'),
          const SizedBox(height: AppDimens.space8),
          _QuickActionsRow(
            onNavigate: widget.onNavigate,
            onFilesIntent: widget.onFilesIntent,
          ),

          // --------------------------------------- active transfer pod
          if (_pendingUploads > 0) ...[
            const SizedBox(height: AppDimens.space24),
            NexaStatusPod(
              icon: Icons.cloud_upload_outlined,
              tint: AppColors.warningFor(Theme.of(context).brightness),
              title:
                  '${Format.count(_pendingUploads, 'item')} waiting to upload',
              subtitle: 'Queued safely; resumes when a connection is available',
              trailing: 'Paused',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TransfersScreen()),
                );
              },
            ),
          ],

          // ------------------------------------------ recent files strip
          const SizedBox(height: AppDimens.space32),
          _RecentSection(
            api: widget.api,
            storage: storage,
            recent: _recent,
            onNavigate: widget.onNavigate,
          ),
          if (_photos.isNotEmpty) ...[
            const SizedBox(height: AppDimens.space32),
            _PhotoStrip(
              photos: _photos,
              thumbnailFor: _photoThumb,
              api: widget.api,
              onOpenLibrary: () => widget.onNavigate(3),
            ),
          ],
          const SizedBox(height: AppDimens.space32),
          _SharedPreview(
            shares: _shared,
            onNavigate: widget.onNavigate,
          ),
          const SizedBox(height: AppDimens.space8),
        ],
      ),
    );
  }
}

/// Quiet date + greeting. Forest appears once, as a small leading mark.
class _EditorialHeader extends StatelessWidget {
  final DateTime now;
  const _EditorialHeader({required this.now});

  static String _dateLabel(DateTime now) {
    final weekday = switch (now.weekday) {
      DateTime.monday => 'Monday',
      DateTime.tuesday => 'Tuesday',
      DateTime.wednesday => 'Wednesday',
      DateTime.thursday => 'Thursday',
      DateTime.friday => 'Friday',
      DateTime.saturday => 'Saturday',
      DateTime.sunday => 'Sunday',
      _ => '',
    };
    final month = switch (now.month) {
      1 => 'January',
      2 => 'February',
      3 => 'March',
      4 => 'April',
      5 => 'May',
      6 => 'June',
      7 => 'July',
      8 => 'August',
      9 => 'September',
      10 => 'October',
      11 => 'November',
      12 => 'December',
      _ => '',
    };
    return '$weekday, $month ${now.day}';
  }

  static String _greeting(int hour) {
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final date = _dateLabel(now);
    final greeting = _greeting(now.hour);

    return Semantics(
      label: '$date. $greeting.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: AppDimens.space8,
                height: AppDimens.space8,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius:
                      BorderRadius.circular(AppDimens.radiusExtraSmall),
                ),
              ),
              const SizedBox(width: AppDimens.space8),
              Text(
                date.toUpperCase(),
                style: AppTextStyle.sectionHeader.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.space12),
          Text(
            greeting,
            style: AppTextStyle.display.copyWith(color: scheme.onSurface),
          ),
          const SizedBox(height: AppDimens.space8),
          Text(
            'A quiet place for everything you keep.',
            style: AppTextStyle.body.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// A single dominant action: pick up the newest file or photo, with a quiet
/// empty state when there is nothing recent.
class _ContinueSection extends StatelessWidget {
  final FileEntry? entry;
  final bool isPhoto;
  final List<FileEntry> siblings;
  final Uint8List? Function(FileEntry entry) thumbnailFor;
  final Api api;
  final int pendingUploads;
  final VoidCallback onUpload;
  final VoidCallback onBrowse;
  final VoidCallback onPhotos;
  final VoidCallback onTransfers;

  const _ContinueSection({
    required this.entry,
    required this.isPhoto,
    required this.siblings,
    required this.thumbnailFor,
    required this.api,
    required this.pendingUploads,
    required this.onUpload,
    required this.onBrowse,
    required this.onPhotos,
    required this.onTransfers,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = entry;

    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionHeader('Continue where you left off'),
          const SizedBox(height: AppDimens.space12),
          if (item == null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (pendingUploads > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppDimens.space8),
                    child: TextButton(
                      onPressed: onTransfers,
                      child: Text(
                        '${Format.count(pendingUploads, 'upload')} in progress',
                      ),
                    ),
                  ),
                Text(
                  'Nothing to pick up yet. Upload a file to begin.',
                  style: AppTextStyle.body.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppDimens.space4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: onUpload,
                    child: const Text('Upload files'),
                  ),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(AppDimens.radiusMedium),
                  onTap: () => FileOpener.open(
                    context,
                    api: api,
                    entry: item,
                    siblings: siblings,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppDimens.space8,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (isPhoto)
                          _ContinueThumb(
                            bytes: thumbnailFor(item),
                            entry: item,
                          )
                        else
                          NexaFileGlyph(
                            name: item.name,
                            type: item.type,
                            size: AppDimens.iconHero,
                            color: scheme.onSurfaceVariant,
                          ),
                        const SizedBox(width: AppDimens.space16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyle.title2.copyWith(
                                  color: scheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: AppDimens.space4),
                              Text(
                                '${isPhoto ? 'Photo · ' : ''}'
                                '${Format.relTime(item.modified)} · '
                                '${Format.bytes(item.size)}',
                                style: AppTextStyle.subheadline.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppDimens.space8),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: AppDimens.iconMedium,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppDimens.space4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: isPhoto ? onPhotos : onBrowse,
                    child: Text(isPhoto ? 'Open library' : 'See all files'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Square thumbnail for the dominant continue tile, with a quiet fallback.
class _ContinueThumb extends StatelessWidget {
  final Uint8List? bytes;
  final FileEntry entry;

  const _ContinueThumb({required this.bytes, required this.entry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
      child: SizedBox(
        width: AppDimens.iconHero + AppDimens.space24,
        height: AppDimens.iconHero + AppDimens.space24,
        child: bytes != null
            ? Image.memory(
                bytes!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                semanticLabel: 'Preview of ${entry.name}',
              )
            : Container(
                color: scheme.surfaceContainerLow,
                alignment: Alignment.center,
                child: Icon(
                  Icons.image_outlined,
                  color: scheme.onSurfaceVariant,
                  size: AppDimens.iconLarge,
                ),
              ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: AppTextStyle.sectionHeader.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// Restrained typographic storage stat. The whole row remains the tap target
/// for Storage Insights; the slim indicator is the only chart on the page.
class _StorageSummary extends StatelessWidget {
  final StorageInfo storage;
  final VoidCallback onTap;
  const _StorageSummary({required this.storage, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final usedBytes = storage.usedBytes;
    final quotaBytes = storage.quotaBytes;
    final hasQuota = quotaBytes != null;
    final (value, unit) = _decompose(usedBytes);
    final primary = '$value $unit';

    final supporting = hasQuota
        ? 'of ${Format.bytes(quotaBytes)} · '
            '${Format.bytes(storage.freeBytes)} free'
        : 'Unlimited storage · ${Format.count(storage.fileCount, 'file')}';

    return Semantics(
      button: true,
      label: 'Storage: $primary $supporting. Open storage insights.',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppDimens.space8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'STORAGE USED',
                          style: AppTextStyle.sectionHeader.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: AppDimens.space4),
                        Text(
                          primary,
                          style: AppTextStyle.metricValue.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppDimens.space8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppDimens.space4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'INSIGHTS',
                          style: AppTextStyle.labelMedium.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: AppDimens.space2),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: AppDimens.iconSmall,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDimens.space8),
              Text(
                supporting,
                style: AppTextStyle.bodySmall.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (hasQuota) ...[
                const SizedBox(height: AppDimens.space12),
                ClipRRect(
                  borderRadius:
                      BorderRadius.circular(AppDimens.radiusExtraSmall),
                  child: LinearProgressIndicator(
                    value: storage.usageFraction.clamp(0.0, 1.0),
                    minHeight: AppDimens.space4,
                    color: Theme.of(context).colorScheme.primary,
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                  ),
                ),
              ],
              const SizedBox(height: AppDimens.space12),
              Divider(
                height: 1,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Splits a byte count into a short number and unit for the big metric
/// ("812.4", "GB").
(String, String) _decompose(num? value) {
  if (value == null) return ('0', 'B');
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  double n = value.toDouble();
  int i = 0;
  while (n >= 1024 && i < units.length - 1) {
    n /= 1024;
    i++;
  }
  final digits = n >= 10 || i == 0 ? 0 : 1;
  return (n.toStringAsFixed(digits), units[i]);
}

/// Quick actions as a compact neutral row; intents still drive My files.
class _QuickActionsRow extends StatelessWidget {
  final ValueChanged<int> onNavigate;
  final ValueChanged<FilesIntent>? onFilesIntent;
  const _QuickActionsRow({required this.onNavigate, this.onFilesIntent});

  /// Falls back to plain navigation if no intent handler was supplied.
  void _request(FilesIntent intent) {
    final handler = onFilesIntent;
    if (handler != null) {
      handler(intent);
    } else {
      onNavigate(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = <_QuickActionData>[
      _QuickActionData(
        Icons.cloud_upload_outlined,
        'Upload files',
        () => _request(FilesIntent.upload),
      ),
      _QuickActionData(
        Icons.drive_folder_upload_outlined,
        'Upload folder',
        () => _request(FilesIntent.uploadFolder),
      ),
      _QuickActionData(
        Icons.create_new_folder_outlined,
        'New folder',
        () => _request(FilesIntent.newFolder),
      ),
      _QuickActionData(
        Icons.photo_library_outlined,
        'Photos',
        () => onNavigate(3),
      ),
    ];

    return SizedBox(
      height: AppDimens.touchTargetLarge,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppDimens.space8),
        itemBuilder: (context, index) {
          final item = items[index];
          return Semantics(
            button: true,
            child: InkWell(
              onTap: item.onTap,
              borderRadius: BorderRadius.circular(AppDimens.radiusSmall),
              child: Container(
                constraints: const BoxConstraints(
                  maxWidth: AppDimens.photoStripTile + AppDimens.space24,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.space12,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(AppDimens.radiusSmall),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.icon,
                      size: AppDimens.iconSmall,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppDimens.space8),
                    Flexible(
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.labelLarge.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
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
    );
  }
}

class _QuickActionData {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _QuickActionData(this.icon, this.title, this.onTap);
}

class _HomeConnectionNotice extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _HomeConnectionNotice({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NexaSurface(
      level: NexaSurfaceLevel.grouped,
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.space16),
        child: Row(
          children: [
            Container(
              width: AppDimens.iconTileLarge,
              height: AppDimens.iconTileLarge,
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(AppDimens.radiusMedium),
              ),
              child: Icon(
                Icons.cloud_off_rounded,
                color: scheme.onErrorContainer,
              ),
            ),
            const SizedBox(width: AppDimens.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Server unavailable',
                    style: AppTextStyle.titleLarge.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppDimens.space4),
                  Text(
                    message,
                    style: AppTextStyle.bodySmall.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

/// A quiet, edge-to-edge photo strip on Home.
class _PhotoStrip extends StatelessWidget {
  final List<FileEntry> photos;
  final Uint8List? Function(FileEntry entry) thumbnailFor;
  final Api api;
  final VoidCallback onOpenLibrary;

  const _PhotoStrip({
    required this.photos,
    required this.thumbnailFor,
    required this.api,
    required this.onOpenLibrary,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: _SectionHeader('Recent photos')),
            TextButton(
              onPressed: onOpenLibrary,
              child: const Text('Open library'),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.space8),
        SizedBox(
          height: AppDimens.photoStripTile,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: photos.length,
            separatorBuilder: (_, __) =>
                const SizedBox(width: AppDimens.space8),
            itemBuilder: (context, index) {
              final entry = photos[index];
              final bytes = thumbnailFor(entry);
              return SizedBox(
                width: AppDimens.photoStripTile,
                child: Material(
                  color: scheme.surfaceContainerLow,
                  borderRadius:
                      BorderRadius.circular(AppDimens.radiusExtraSmall),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => FileOpener.open(
                      context,
                      api: api,
                      entry: entry,
                      siblings: photos,
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (bytes != null)
                          Image.memory(
                            bytes,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            semanticLabel: 'Preview of ${entry.name}',
                          )
                        else
                          Center(
                            child: NexaFileGlyph(
                              name: entry.name,
                              type: entry.type,
                              size: 36,
                            ),
                          ),
                        if (entry.category == Category.video)
                          Positioned(
                            right: AppDimens.space6,
                            bottom: AppDimens.space6,
                            child: Icon(
                              Icons.play_circle_outlined,
                              color: scheme.onPrimary,
                              size: AppDimens.iconMedium,
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
    );
  }
}

/// Personal, compact shared-with-me preview for Home.
class _SharedPreview extends StatelessWidget {
  final List<Map<String, dynamic>> shares;
  final ValueChanged<int> onNavigate;

  const _SharedPreview({required this.shares, required this.onNavigate});

  String _name(Map<String, dynamic> share) {
    final path = share['path']?.toString() ?? '';
    final name = path.split('/').last;
    return name.isEmpty ? 'Shared item' : name;
  }

  String _subtitle(Map<String, dynamic> share) {
    final owner =
        (share['owner'] ?? share['owner_username'])?.toString().trim() ?? '';
    final permission =
        share['permission']?.toString() == 'write' ? 'Can edit' : 'Can view';
    final from = owner.isEmpty ? 'Shared with you' : 'Shared by $owner';
    return '$from · $permission';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visible = shares.take(3).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: _SectionHeader('Shared with me')),
            TextButton(
              onPressed: () => onNavigate(2),
              child: const Text('See all'),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.space8),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppDimens.space12),
            child: Text(
              'Files others share with you will appear here.',
              style: AppTextStyle.bodySmall.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          )
        else
          Column(
            children: [
              for (var i = 0; i < visible.length; i++) ...[
                NexaSharedTile(
                  name: _name(visible[i]),
                  path: visible[i]['path']?.toString() ?? '',
                  isFolder: FileEntry.kindOf(visible[i]) == 'folder',
                  person: (visible[i]['owner'] ?? visible[i]['owner_username'])
                      ?.toString(),
                  subtitle: _subtitle(visible[i]),
                  onTap: () => onNavigate(2),
                ),
                if (i < visible.length - 1)
                  Divider(
                    height: 1,
                    color: scheme.outlineVariant,
                    indent: AppDimens.rowInset +
                        AppDimens.iconTileLarge +
                        AppDimens.space16,
                    endIndent: AppDimens.rowInset,
                  ),
              ],
            ],
          ),
      ],
    );
  }
}

/// Real recently-modified files from the root folder, shown as a horizontal
/// editorial strip rather than a stack of cards.
class _RecentSection extends StatelessWidget {
  final Api api;
  final StorageInfo? storage;
  final List<FileEntry> recent;
  final ValueChanged<int> onNavigate;
  const _RecentSection({
    required this.api,
    required this.storage,
    required this.recent,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final empty = storage != null && storage!.fileCount == 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: _SectionHeader('Recent files')),
            TextButton(
              onPressed: () => onNavigate(1),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('See all', style: AppTextStyle.labelLarge),
                  const SizedBox(width: AppDimens.space2),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: AppDimens.iconSmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.space8),
        if (empty || recent.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppDimens.space12),
            child: Text(
              empty
                  ? 'Upload your first files to get started.'
                  : 'Files you open or update will appear here.',
              style: AppTextStyle.bodySmall.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          )
        else
          SizedBox(
            height: AppDimens.touchTargetLarge + AppDimens.space24,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: recent.length,
              separatorBuilder: (_, __) => SizedBox(
                width: AppDimens.space16,
                child: Center(
                  child: Container(
                    width: 1,
                    height: AppDimens.iconLarge,
                    color: scheme.outlineVariant,
                  ),
                ),
              ),
              itemBuilder: (context, index) {
                final entry = recent[index];
                return SizedBox(
                  width: AppDimens.photoStripTile + AppDimens.space24,
                  child: InkWell(
                    onTap: () => FileOpener.open(
                      context,
                      api: api,
                      entry: entry,
                      siblings: recent,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        NexaFileGlyph(
                          name: entry.name,
                          type: entry.type,
                          size: AppDimens.iconLarge,
                        ),
                        const SizedBox(height: AppDimens.space8),
                        Text(
                          entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.bodyEmphasized.copyWith(
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: AppDimens.space2),
                        Text(
                          '${Format.relTime(entry.modified)} · '
                          '${Format.bytes(entry.size)}',
                          style: AppTextStyle.footnote.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
