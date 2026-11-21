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
import '../../widgets/nexa_motion.dart';
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

  /// Thumbnail cache for the small photo strip on the dashboard.
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

  /// Sharing is optional dashboard context. A failed shared listing must never
  /// blank the storage and files overview.
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
      // The dashboard still works when the photo library is unavailable.
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

  /// A stable identity for whichever storage-hero state is showing.
  String get _heroState {
    if (_storage != null) return 'ready';
    return _loading ? 'loading' : 'error';
  }

  @override
  Widget build(BuildContext context) {
    final storage = _storage;

    final pageTitle =
        MediaQuery.sizeOf(context).width >= 900 ? 'Overview' : 'NexaDrive';

    final colorScheme = Theme.of(context).colorScheme;

    return NexaPage(
      title: pageTitle,
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
          // ------------------------- storage hero + quick actions entrance
          // One bounded, non-repeating stagger on the first screenful only.
          NexaStagger(
            children: [
              NexaStateSwitcher(
                stateKey: ValueKey(_heroState),
                child: storage != null
                    ? NexaSurface(
                        level: NexaSurfaceLevel.grouped,
                        radius: AppDimens.radiusLarge,
                        padding: const EdgeInsets.all(AppDimens.space16),
                        child: _StorageHero(
                          storage: storage,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  StorageInsightsScreen(api: widget.api),
                            ),
                          ),
                        ),
                      )
                    : _loading
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.only(top: AppDimens.space40),
                              child: NexaCircularProgress(
                                size: AppDimens.iconMedium,
                              ),
                            ),
                          )
                        : _HomeConnectionNotice(
                            message: _error ??
                                'Check your connection and try again.',
                            onRetry: load,
                          ),
              ),
              // --------------------------------- quick actions (focus blocks)
              const SizedBox(height: AppDimens.space24),
              const _SectionHeader('Quick actions'),
              const SizedBox(height: AppDimens.space12),
              _QuickActionsGrid(
                onNavigate: widget.onNavigate,
                onFilesIntent: widget.onFilesIntent,
              ),
            ],
          ),
          const SizedBox(height: AppDimens.space24),

          // ---------------------------------------- active transfer pod
          if (_pendingUploads > 0) ...[
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
            const SizedBox(height: AppDimens.space24),
          ],

          // -------------------------------------------------- recent files
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
        ],
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

/// Storage hero in the viewing area: reads the metric and the remaining space
/// in one glance; the whole card is the interaction target.
class _StorageHero extends StatelessWidget {
  final StorageInfo storage;
  final VoidCallback onTap;
  const _StorageHero({required this.storage, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final usedBytes = storage.usedBytes;
    final quotaBytes = storage.quotaBytes;
    final hasQuota = quotaBytes != null;
    final (value, _) = _decompose(usedBytes);

    final secondary = hasQuota ? 'of ${Format.bytes(quotaBytes)} used' : null;
    final detail = hasQuota
        ? '${Format.bytes(storage.freeBytes)} free · '
            '${Format.count(storage.fileCount, 'file')}'
        : 'Unlimited storage · ${Format.count(storage.fileCount, 'file')}';

    return NexaHero(
      label: 'Storage',
      value: value,
      secondary: secondary,
      detail: detail,
      fraction: hasQuota ? storage.usageFraction : 0,
      onTap: onTap,
      actionLabel: 'INSIGHTS',
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

/// Quick actions as a calm 2×2 gallery, matching the visual rhythm of a photo
/// library rather than a list of settings rows.
class _QuickActionsGrid extends StatelessWidget {
  final ValueChanged<int> onNavigate;
  final ValueChanged<FilesIntent>? onFilesIntent;
  const _QuickActionsGrid({required this.onNavigate, this.onFilesIntent});

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
        'Add to your cloud',
        () => _request(FilesIntent.upload),
      ),
      _QuickActionData(
        Icons.drive_folder_upload_outlined,
        'Upload folder',
        'Keep folders together',
        () => _request(FilesIntent.uploadFolder),
      ),
      _QuickActionData(
        Icons.create_new_folder_outlined,
        'New folder',
        'Organise your space',
        () => _request(FilesIntent.newFolder),
      ),
      _QuickActionData(
        Icons.photo_library_outlined,
        'Photo library',
        'Your memories, together',
        () => onNavigate(3),
      ),
    ];

    return GridView.count(
      // The shell exposes pill clearance through MediaQuery.padding.bottom.
      // A scrollable grid would otherwise consume that inset as trailing
      // sliver padding, leaving a large empty band after the quick actions.
      padding: EdgeInsets.zero,
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppDimens.space12,
      crossAxisSpacing: AppDimens.space12,
      childAspectRatio: 2.4,
      children: [
        for (final item in items) _QuickActionTile(data: item),
      ],
    );
  }
}

class _QuickActionData {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickActionData(
    this.icon,
    this.title,
    this.subtitle,
    this.onTap,
  );
}

class _QuickActionTile extends StatelessWidget {
  final _QuickActionData data;
  const _QuickActionTile({required this.data});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NexaSurface(
      level: NexaSurfaceLevel.grouped,
      radius: AppDimens.radiusMedium,
      padding: const EdgeInsets.all(AppDimens.space12),
      onTap: data.onTap,
      child: Row(
        children: [
          Container(
            width: AppDimens.iconTile,
            height: AppDimens.iconTile,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
            ),
            child: Icon(
              data.icon,
              size: AppDimens.iconMedium,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: AppDimens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  data.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.rowTitle.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: AppDimens.space2),
                Text(
                  data.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.bodySmall.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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

/// A quiet, edge-to-edge photo strip on the dashboard.
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
        const SizedBox(height: AppDimens.space12),
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

/// Personal, compact shared-with-me preview for the dashboard.
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

/// Real recently-modified files from the root folder, with a friendly empty
/// state that never pretends data is loading.
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: _SectionHeader('Recent')),
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
        if (storage != null && storage!.fileCount == 0)
          NexaSurface(
            level: NexaSurfaceLevel.grouped,
            radius: AppDimens.radiusCard,
            padding: const EdgeInsets.all(AppDimens.space20),
            child: Column(
              children: [
                Icon(
                  Icons.cloud_done_outlined,
                  size: AppDimens.iconTile,
                  color: scheme.primary,
                ),
                const SizedBox(height: AppDimens.space12),
                Text(
                  'Nothing here yet',
                  style: AppTextStyle.titleMedium.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: AppDimens.space4),
                Text(
                  'Upload your first files to get started.',
                  style: AppTextStyle.bodySmall.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          )
        else if (recent.isEmpty)
          NexaEmptyState(
            icon: Icons.folder_open_rounded,
            title: 'No recent files',
            hint: 'Files you open or update will appear here.',
            actionLabel: 'Browse files',
            onAction: () => onNavigate(1),
          )
        else
          NexaSurface(
            level: NexaSurfaceLevel.grouped,
            radius: AppDimens.radiusCard,
            child: Column(
              children: [
                for (var index = 0; index < recent.length; index++) ...[
                  NexaFileTile(
                    entry: recent[index],
                    showChevron: true,
                    subtitle: '${Format.relTime(recent[index].modified)} · '
                        '${Format.bytes(recent[index].size)}',
                    // Open the actual file from Home without making users
                    // navigate back through the folder hierarchy.
                    onTap: (entry) => FileOpener.open(
                      context,
                      api: api,
                      entry: entry,
                      siblings: recent,
                    ),
                  ),
                  if (index < recent.length - 1)
                    Divider(
                      indent: AppDimens.iconTileLarge + AppDimens.space24,
                      endIndent: AppDimens.space16,
                      color: scheme.outlineVariant,
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
