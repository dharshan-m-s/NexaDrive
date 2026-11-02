import 'package:flutter/material.dart';
import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_dimensions.dart';
import '../../../../core/design/app_typography.dart';
import '../../../../core/models/file_entry.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/file_kind.dart';
import '../../../services/api.dart';
import '../../../services/session.dart';
import '../../../services/upload_manager.dart';
import '../../navigation/file_opener.dart';
import '../../widgets/nexa_components.dart';
import '../files/files_screen.dart' show FilesIntent;
import '../transfers/transfers_screen.dart';

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

  /// The upload queue this screen shows.
  late final UploadManager _manager;

  @override
  void initState() {
    super.initState();
    _manager = UploadManager.current;
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
      ]);
      if (!mounted) return;
      setState(() {
        _storage = StorageInfo.fromJson(results[0] as Map<String, dynamic>);
        _pendingUploads = results[1] as int;
        _recent = (results[2] as List<FileEntry>);
        _loading = false;
      });
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

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  /// A stable identity for whichever storage-hero state is showing.
  String get _heroState {
    if (_storage != null) return 'ready';
    return _loading ? 'loading' : 'error';
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.session.displayName?.trim().isNotEmpty == true
        ? widget.session.displayName!
        : widget.session.username ?? 'there';

    final storage = _storage;

    return NexaPage(
      title: '${_greeting()}, $name',
      bottomSafeArea: false,
      subtitle: storage == null
          ? 'Your private cloud'
          : '${Format.bytes(storage.usedBytes)} used · '
              '${Format.count(storage.fileCount, 'file')}',
      scrollable: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ------------------------------------------------- storage hero
          NexaStateSwitcher(
            stateKey: ValueKey(_heroState),
            child: storage != null
                ? _StorageHero(
                    storage: storage,
                    onTap: () => widget.onNavigate(1),
                  )
                : _loading
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.only(top: AppDimens.space40),
                          child: NexaCircularProgress(size: 20),
                        ),
                      )
                    : NexaEmptyState(
                        icon: Icons.cloud_off_rounded,
                        title: 'Can\'t reach your server',
                        hint: _error ?? 'Check your connection and try again.',
                        actionLabel: 'Retry',
                        onAction: load,
                      ),
          ),
          const SizedBox(height: AppDimens.space24),

          // ------------------------------------- quick actions (focus blocks)
          const _SectionHeader('Quick actions'),
          const SizedBox(height: AppDimens.space12),
          _QuickActionsGrid(
            onNavigate: widget.onNavigate,
            onFilesIntent: widget.onFilesIntent,
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
    final brightness = Theme.of(context).brightness;
    return Text(
      title,
      style: AppTextStyle.sectionHeader.copyWith(
        color: AppColors.labelPrimaryFor(brightness),
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
    final hasQuota = quotaBytes != null && quotaBytes > 0;
    final (value, unit) = _decompose(usedBytes);

    final secondary = hasQuota ? 'of ${Format.bytes(quotaBytes)} used' : null;
    final detail = hasQuota
        ? '${Format.bytes(storage.freeBytes)} free · '
            '${Format.count(storage.fileCount, 'file')}'
        : 'Storage quota is not set on this server';

    return NexaHero(
      label: 'Storage',
      value: value,
      secondary: secondary,
      detail: detail,
      fraction: hasQuota ? storage.usageFraction : 0,
      onTap: onTap,
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

/// Quick actions as vertical focus blocks — 2 across on phones, more on wide
/// screens. Each block is a comfortable interaction target.
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
    final items = <NexaFocusBlock>[
      NexaFocusBlock(
        icon: Icons.cloud_upload_outlined,
        title: 'Upload',
        layout: NexaFocusBlockLayout.vertical,
        onTap: () => _request(FilesIntent.upload),
      ),
      NexaFocusBlock(
        icon: Icons.drive_folder_upload_outlined,
        title: 'Upload folder',
        layout: NexaFocusBlockLayout.vertical,
        onTap: () => _request(FilesIntent.uploadFolder),
      ),
      NexaFocusBlock(
        icon: Icons.create_new_folder_outlined,
        title: 'New folder',
        layout: NexaFocusBlockLayout.vertical,
        onTap: () => _request(FilesIntent.newFolder),
      ),
      NexaFocusBlock(
        icon: Icons.photo_library_outlined,
        title: 'Photo library',
        layout: NexaFocusBlockLayout.vertical,
        onTap: () => onNavigate(3),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final columns = maxWidth >= 800 ? 4 : 2;
        const spacing = AppDimens.space12;
        final width = (maxWidth - (columns - 1) * spacing) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in items) SizedBox(width: width, child: item),
          ],
        );
      },
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
    final brightness = Theme.of(context).brightness;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader('Recent'),
        const SizedBox(height: AppDimens.space12),
        if (storage != null && storage!.fileCount == 0)
          NexaSurface(
            level: NexaSurfaceLevel.grouped,
            radius: AppDimens.radiusMedium,
            padding: const EdgeInsets.all(AppDimens.space20),
            child: Column(
              children: [
                Icon(
                  Icons.cloud_done_outlined,
                  size: 40,
                  color: AppColors.accentFor(brightness),
                ),
                const SizedBox(height: AppDimens.space12),
                Text(
                  'Nothing here yet',
                  style: AppTextStyle.sectionHeader.copyWith(
                    color: AppColors.labelPrimaryFor(brightness),
                  ),
                ),
                const SizedBox(height: AppDimens.space4),
                Text(
                  'Upload your first files to get started.',
                  style: AppTextStyle.caption1.copyWith(
                    color: AppColors.labelSecondaryFor(brightness),
                  ),
                ),
              ],
            ),
          )
        else if (recent.isEmpty)
          NexaEmptyState(
            icon: Icons.folder_open_rounded,
            title: 'Your files are ready',
            hint: 'Browse everything stored in your private cloud.',
            actionLabel: 'Open My files',
            onAction: () => onNavigate(1),
          )
        else
          Column(
            children: [
              for (final entry in recent)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppDimens.space8),
                  child: NexaFocusBlock(
                    icon: FileKind.icon(entry.category),
                    tint: FileKind.tint(entry.category, brightness),
                    title: entry.name,
                    subtitle:
                        '${Format.relTime(entry.modified)} · ${Format.bytes(entry.size)}',
                    showChevron: true,
                    // Open the actual file. Jumping to My files and leaving the
                    // user to find it again is not "Recent".
                    onTap: () => FileOpener.open(
                      context,
                      api: api,
                      entry: entry,
                      siblings: recent,
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
