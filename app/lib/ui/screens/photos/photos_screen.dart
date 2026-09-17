import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/models/file_entry.dart';
import '../../../core/utils/format.dart';
import '../../../services/api.dart';
import '../../../services/session.dart';
import '../../../services/thumbnail_cache.dart';
import '../../widgets/one_ui_action_bar.dart';
import '../../widgets/one_ui_empty_state.dart';
import '../../widgets/one_ui_page.dart';
import '../files/file_share_sheet.dart';
import 'photo_viewer.dart';

class PhotosScreen extends StatefulWidget {
  final Api api;
  final Session session;
  const PhotosScreen({super.key, required this.api, required this.session});

  @override
  State<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends State<PhotosScreen> {
  List<Map<String, dynamic>> _photos = [];
  final Map<String, Uint8List> _thumbCache = {};
  ThumbnailCache? _diskCache;
  bool _loading = true;
  String? _error;

  bool _selecting = false;
  final Set<String> _selected = <String>{};

  @override
  void initState() {
    super.initState();
    _openDiskCache();
    load();
  }

  Future<void> _openDiskCache() async {
    try {
      final cache = await ThumbnailCache.open();
      if (mounted) setState(() => _diskCache = cache);
    } catch (_) {}
  }

  Future<void> load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final photos = await widget.api.photos();
      if (!mounted) return;
      setState(() {
        _photos = photos;
        _loading = false;
      });
      for (final p in photos.take(40)) {
        final path = p['path'] as String;
        if (_thumbCache.containsKey(path)) continue;
        await _loadThumb(path);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadThumb(String path) async {
    final serverUrl = widget.session.serverUrl ?? '';
    final disk = _diskCache;
    if (disk != null) {
      final cached = disk.readSync(serverUrl, path);
      if (cached != null) {
        if (mounted) setState(() => _thumbCache[path] = cached);
        return;
      }
    }
    try {
      final bytes = await widget.api.thumbnail(path);
      if (!mounted) return;
      setState(() => _thumbCache[path] = bytes);
      unawaited(disk?.write(serverUrl, path, bytes));
    } catch (e) {
      // 415 (no server-side thumbnail for this format) falls back to the full
      // image so HEIC/AVIF previews still work.
      if (e is ApiException && e.status == 415) {
        try {
          final bytes = await widget.api.download(path);
          if (!mounted) return;
          setState(() => _thumbCache[path] = bytes);
        } catch (_) {}
      }
    }
  }

  void _open(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoViewer(
          photos: _photos,
          initialIndex: index,
          api: widget.api,
        ),
      ),
    );
  }

  // ------------------------------------------------------------ selection
  void _onCellTap(int index, String path) {
    if (_selecting) {
      _toggleSelect(path);
    } else {
      _open(index);
    }
  }

  void _onCellLongPress(String path) {
    if (!_selecting) {
      setState(() {
        _selecting = true;
        _selected.add(path);
      });
    }
  }

  void _toggleSelect(String path) {
    setState(() {
      if (_selected.contains(path)) {
        _selected.remove(path);
      } else {
        _selected.add(path);
      }
    });
  }

  Future<void> _deleteSelected() async {
    final count = _selected.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move to Trash'),
        content: Text(count == 1 ? 'Move 1 photo to trash?' : 'Move $count photos to trash?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Trash'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await widget.api.batch(action: 'delete', paths: _selected.toList());
      _exitSelection();
      await load();
    } catch (e) {
      if (mounted) _toast(e.toString());
    }
  }

  Future<void> _shareSelected() async {
    final entries = _photos
        .where((p) => _selected.contains(p['path']))
        .map(FileEntry.fromJson)
        .toList();
    if (entries.isEmpty) return;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FileShareSheet(api: widget.api, files: entries),
    );
    if (mounted) _exitSelection();
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // -------------------------------------------------------------- grouping
  List<(String, List<Map<String, dynamic>>)> get _groups {
    final sorted = [..._photos]..sort((a, b) {
        final da = DateTime.tryParse(a['modified_at']?.toString() ?? '');
        final db = DateTime.tryParse(b['modified_at']?.toString() ?? '');
        return (db ?? DateTime(1970)).compareTo(da ?? DateTime(1970));
      });
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final p in sorted) {
      final t = DateTime.tryParse(p['modified_at']?.toString() ?? '');
      final key = t == null ? 'Unknown' : _monthLabel(t);
      groups.putIfAbsent(key, () => []).add(p);
    }
    return groups.entries
        .map((e) => (e.key, e.value))
        .toList(growable: false);
  }

  String _monthLabel(DateTime t) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[t.month - 1]} ${t.year}';
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final photoCount = _photos.length;

    return OneUiPage(
      title: _selecting ? Format.count(_selected.length, 'photo') : 'Photos',
      subtitle: _selecting
          ? 'Tap photos to include or exclude'
          : photoCount == 0
              ? 'All your photos in one place'
              : Format.count(photoCount, 'photo'),
      headerAction: _selecting
          ? IconButton(
              tooltip: 'Cancel selection',
              onPressed: _exitSelection,
              icon: const Icon(Icons.close_rounded),
            )
          : IconButton(
              tooltip: 'Refresh',
              onPressed: load,
              icon: Icon(Icons.refresh_rounded, color: AppColors.accentFor(brightness)),
            ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return OneUiEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Can\'t load photos',
        hint: _error,
        actionLabel: 'Retry',
        onAction: load,
      );
    }
    if (_photos.isEmpty) {
      return OneUiEmptyState(
        icon: Icons.photo_library_outlined,
        title: 'No photos yet',
        hint: 'Upload photos from My files and they\'ll appear here.',
        actionLabel: 'Refresh',
        onAction: load,
      );
    }

    final groups = _groups;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: load,
            child: ListView(
              padding: const EdgeInsets.only(bottom: AppDimens.space24),
              children: [
                for (final (label, items) in groups) ...[
                  _MonthHeader(label: label, count: items.length),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 190,
                      mainAxisSpacing: AppDimens.space4,
                      crossAxisSpacing: AppDimens.space4,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, i) => _PhotoCell(
                      path: items[i]['path'] as String,
                      bytes: _thumbFor(items[i]['path'] as String),
                      selected: _selected.contains(items[i]['path']),
                      selecting: _selecting,
                      onTap: () => _onCellTap(
                        _photos.indexOf(items[i]),
                        items[i]['path'] as String,
                      ),
                      onLongPress: () => _onCellLongPress(items[i]['path'] as String),
                    ),
                  ),
                  const SizedBox(height: AppDimens.space16),
                ],
              ],
            ),
          ),
        ),
        if (_selecting)
          OneUiActionBar(
            leading: IconButton(
              tooltip: 'Cancel selection',
              onPressed: _exitSelection,
              icon: const Icon(Icons.close_rounded),
            ),
            title: Format.count(_selected.length, 'photo'),
            actions: [
              OneUiActionItem(
                icon: Icons.share_outlined,
                label: 'Share',
                onTap: _shareSelected,
              ),
              OneUiActionItem(
                icon: Icons.delete_outline_rounded,
                label: 'Trash',
                color: AppColors.errorFor(Theme.of(context).brightness),
                onTap: _deleteSelected,
              ),
            ],
          ),
      ],
    );
  }

  Uint8List? _thumbFor(String path) => _thumbCache[path];
}

class _MonthHeader extends StatelessWidget {
  final String label;
  final int count;
  const _MonthHeader({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.space4, AppDimens.space12, AppDimens.space4, AppDimens.space8,
      ),
      child: Row(
        children: [
          Text(
            label,
            style: AppTextStyle.sectionHeader.copyWith(
              color: AppColors.textPrimaryFor(brightness),
            ),
          ),
          const SizedBox(width: AppDimens.space8),
          Text(
            Format.count(count, 'photo'),
            style: AppTextStyle.caption.copyWith(
              color: AppColors.textSecondaryFor(brightness),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single gallery cell: rounded, cover-cropped, with selection chrome.
class _PhotoCell extends StatelessWidget {
  final String path;
  final Uint8List? bytes;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _PhotoCell({
    required this.path,
    required this.bytes,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final onAccent = AppColors.onAccentContainerFor(brightness);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppDimens.radiusInner),
            child: bytes == null
                ? Container(
                    color: brightness == Brightness.dark
                        ? AppColors.surfaceAltDark
                        : AppColors.surfaceAltLight,
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Image.memory(
                    bytes!,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.high,
                    gaplessPlayback: true,
                  ),
          ),
          if (selected)
            _SelectedOverlay(brightness: brightness, onAccent: onAccent),
        ],
      ),
    );
  }
}

class _SelectedOverlay extends StatelessWidget {
  final Brightness brightness;
  final Color onAccent;
  const _SelectedOverlay({required this.brightness, required this.onAccent});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppDimens.radiusInner),
        border: Border.all(color: const Color(0xFF0B87D0), width: 2.5),
        color: brightness == Brightness.dark
            ? AppColors.accentDark.withValues(alpha: 0.30)
            : AppColors.accentContainerLight.withValues(alpha: 0.45),
      ),
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.space6),
          child: Icon(
            Icons.check_circle_rounded,
            color: onAccent,
            size: 22,
          ),
        ),
      ),
    );
  }
}