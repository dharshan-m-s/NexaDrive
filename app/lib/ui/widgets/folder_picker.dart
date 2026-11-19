import 'package:flutter/material.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';
import '../../core/models/file_entry.dart';
import '../../services/api.dart';
import 'nexa_components.dart';

/// Material 3 folder picker that browses the user's server directory tree.
///
/// Returns the server-relative destination path ("" = My files root) when a
/// folder is picked, or null if cancelled. Browsing is done through the API,
/// so destinations are always valid server paths — never local device paths.
class FolderPicker extends StatefulWidget {
  final Api api;
  final String initialPath;

  const FolderPicker({super.key, required this.api, this.initialPath = ''});

  static Future<String?> pick(
    BuildContext context, {
    required Api api,
    required String title,
    String initialPath = '',
  }) async {
    final path = await showNexaFormSheet<String>(
      context,
      builder: (_) => FolderPickerBody(
        api: api,
        title: title,
        initialPath: initialPath,
      ),
    );
    return path;
  }

  @override
  State<FolderPicker> createState() => _FolderPickerState();
}

class _FolderPickerState extends State<FolderPicker> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// ---------------------------------------------------------------------------
// The real sheet body (kept as a separate StatefulWidget to keep pick logic
// separated from the modal scaffolding).
// ---------------------------------------------------------------------------
class FolderPickerBody extends StatefulWidget {
  final Api api;
  final String title;
  final String initialPath;

  const FolderPickerBody({
    super.key,
    required this.api,
    required this.title,
    required this.initialPath,
  });

  @override
  State<FolderPickerBody> createState() => _FolderPickerBodyState();
}

class _FolderPickerBodyState extends State<FolderPickerBody> {
  String _path = '';
  List<FileEntry> _folders = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _path = widget.initialPath;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.api.listFiles(_path);
      if (!mounted) return;
      setState(() {
        _folders =
            items.map(FileEntry.fromJson).where((e) => e.isFolder).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _navigateTo(String path) {
    setState(() => _path = path);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final titleText = _path.isEmpty ? widget.title : _path;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: AppDimens.space8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.pageMargin,
                AppDimens.space8,
                AppDimens.pageMargin,
                AppDimens.space4,
              ),
              child: Row(
                children: [
                  if (_path.isNotEmpty)
                    IconButton(
                      tooltip: 'Up one level',
                      onPressed: () {
                        final p = _path;
                        final idx = p.lastIndexOf('/');
                        _navigateTo(idx < 0 ? '' : p.substring(0, idx));
                      },
                      style: IconButton.styleFrom(
                        backgroundColor: scheme.surfaceContainerHigh,
                      ),
                      icon: const Icon(Icons.arrow_upward_rounded),
                    )
                  else
                    SizedBox(
                      width: AppDimens.touchTarget,
                      height: AppDimens.touchTarget,
                      child: Center(
                        child: NexaFileGlyph.folder(
                          size: AppDimens.iconTileLarge,
                        ),
                      ),
                    ),
                  const SizedBox(width: AppDimens.space12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DESTINATION',
                          style: AppTextStyle.labelMedium.copyWith(
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(height: AppDimens.space2),
                        Text(
                          titleText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.titleMedium.copyWith(
                            color: scheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Use this folder',
                    onPressed: _loading
                        ? null
                        : () => Navigator.of(context).pop(_path),
                    icon: const Icon(Icons.check_rounded),
                  ),
                ],
              ),
            ),
            if (_path.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.pageMargin),
                child: Text(
                  'Moving here keeps your files on this server path.',
                  style: AppTextStyle.bodySmall.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: AppDimens.space8),
            Flexible(
              child: _buildList(),
            ),
            const SizedBox(height: AppDimens.space8),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.pageMargin,
                0,
                AppDimens.pageMargin,
                AppDimens.space12,
              ),
              child: FilledButton(
                onPressed:
                    _loading ? null : () => Navigator.of(context).pop(_path),
                child: Text('Move to $titleText'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    final scheme = Theme.of(context).colorScheme;

    if (_loading) {
      return const SizedBox(
        height: 180,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_error != null) {
      return SizedBox(
        height: 180,
        child: NexaEmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Can\'t load folders',
          hint: _error,
          actionLabel: 'Retry',
          onAction: _load,
        ),
      );
    }
    if (_folders.isEmpty) {
      return const SizedBox(
        height: 180,
        child: NexaEmptyState(
          icon: Icons.folder_open_rounded,
          title: 'No subfolders',
          hint: 'This folder is ready to use as a destination.',
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.pageMargin),
      itemCount: _folders.length,
      itemBuilder: (context, i) {
        final folder = _folders[i];
        return ListTile(
          onTap: () => _navigateTo(folder.path),
          leading: SizedBox(
            width: AppDimens.iconTileLarge,
            height: AppDimens.iconTileLarge,
            child: Center(
              child: NexaFileGlyph.folder(size: 36),
            ),
          ),
          title: Text(
            folder.name,
            style: AppTextStyle.titleMedium.copyWith(color: scheme.onSurface),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: scheme.onSurfaceVariant,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusSmall),
          ),
          minTileHeight: AppDimens.listHeight,
        );
      },
    );
  }
}
