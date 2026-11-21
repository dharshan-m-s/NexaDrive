import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';
import '../../core/models/file_entry.dart';
import '../../core/utils/format.dart';
import 'nexa_file_glyph.dart';

/// Continuous file row and media-library grid item.
///
/// The row uses a single divider, a strong filename and quiet metadata. The
/// grid item is a preview with the name underneath — never a dashboard card.
class NexaFileTile extends StatelessWidget {
  final FileEntry entry;
  final ValueChanged<FileEntry>? onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<FileEntry>? onSecondaryTap;
  final ValueChanged<FileEntry>? onHoverEnter;
  final VoidCallback? onHoverExit;
  final bool selected;
  final bool selecting;
  final Widget? trailing;
  final String? subtitle;
  final bool showChevron;
  final Uint8List? thumbnail;

  /// Adds a dedicated select control beside the preview in list rows.
  ///
  /// Callers that do not support selection leave this null and keep the compact
  /// selection badge used by Home and Search.
  final VoidCallback? onSelectToggle;

  const NexaFileTile({
    super.key,
    required this.entry,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.onHoverEnter,
    this.onHoverExit,
    this.selected = false,
    this.selecting = false,
    this.trailing,
    this.subtitle,
    this.showChevron = true,
    this.thumbnail,
    this.onSelectToggle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final details = subtitle ?? _metadata(context, entry);

    return Semantics(
      button: true,
      selected: selected,
      label: '${entry.name}, $details',
      hint: selecting
          ? 'Toggles selection'
          : 'Opens ${entry.isFolder ? 'folder' : 'file'}. Long press and drag to select several.',
      child: Material(
        color: selected ? scheme.primaryContainer : Colors.transparent,
        child: InkWell(
          onTap: onTap == null ? null : () => onTap!(entry),
          onLongPress: onLongPress,
          onSecondaryTap:
              onSecondaryTap == null ? null : () => onSecondaryTap!(entry),
          onHover: (hovering) {
            if (hovering) {
              onHoverEnter?.call(entry);
            } else {
              onHoverExit?.call();
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.rowInset,
              vertical: AppDimens.space10,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _leading(),
                const SizedBox(width: AppDimens.space16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.rowTitle.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: AppDimens.space4),
                      Text(
                        details,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.bodySmall.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: AppDimens.space8),
                  trailing!,
                ] else if (entry.isFolder && showChevron)
                  Icon(
                    Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant,
                    size: AppDimens.iconSmall,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _leading() {
    if (selecting && onSelectToggle != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SelectionToggle(
            name: entry.name,
            selected: selected,
            onTap: onSelectToggle!,
          ),
          const SizedBox(width: AppDimens.space4),
          _FileLeading(entry: entry, thumbnail: thumbnail),
        ],
      );
    }
    if (selecting) return _SelectionBadge(selected: selected);
    return _FileLeading(entry: entry, thumbnail: thumbnail);
  }

  static String _metadata(BuildContext context, FileEntry entry) {
    final parts = <String>[];
    if (entry.isFolder) {
      parts.add('Folder');
    } else if (entry.size != null) {
      parts.add(Format.bytes(entry.size));
    }
    final modified = Format.relTime(entry.modified);
    if (modified.isNotEmpty) parts.add(modified);
    return parts.isEmpty
        ? (entry.isFolder ? 'Folder' : 'File')
        : parts.join(' · ');
  }
}

class _FileLeading extends StatelessWidget {
  final FileEntry entry;
  final Uint8List? thumbnail;

  const _FileLeading({required this.entry, this.thumbnail});

  @override
  Widget build(BuildContext context) {
    if (thumbnail != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
        child: Image.memory(
          thumbnail!,
          width: AppDimens.iconTile,
          height: AppDimens.iconTile,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          cacheWidth:
              (AppDimens.iconTile * MediaQuery.devicePixelRatioOf(context))
                  .round(),
          errorBuilder: (_, __, ___) => _glyph(context),
        ),
      );
    }
    return _glyph(context);
  }

  Widget _glyph(BuildContext context) => SizedBox(
        width: AppDimens.iconTile,
        height: AppDimens.iconTile,
        child: Center(
          child: entry.isFolder
              ? const NexaFileGlyph.folder(size: 36)
              : NexaFileGlyph(name: entry.name, type: entry.type, size: 36),
        ),
      );
}

class _SelectionBadge extends StatelessWidget {
  final bool selected;

  const _SelectionBadge({required this.selected});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: AppDimens.iconMedium,
      height: AppDimens.iconMedium,
      child: Icon(
        selected ? Icons.check_circle_rounded : Icons.circle_outlined,
        color: selected ? scheme.primary : scheme.onSurfaceVariant,
        size: AppDimens.iconMedium,
      ),
    );
  }
}

/// A 48dp selection handle that sits beside, rather than replaces, the preview.
class _SelectionToggle extends StatelessWidget {
  final String name;
  final bool selected;
  final VoidCallback onTap;

  const _SelectionToggle({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: AppDimens.touchTarget,
      height: AppDimens.touchTarget,
      child: IconButton(
        tooltip: 'Select $name',
        onPressed: onTap,
        icon: Icon(
          selected ? Icons.check_circle_rounded : Icons.circle_outlined,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
          size: AppDimens.iconMedium,
        ),
      ),
    );
  }
}

/// Grid tile for the Files library view.
class NexaFileGridTile extends StatelessWidget {
  final FileEntry entry;
  final ValueChanged<FileEntry>? onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<FileEntry>? onSecondaryTap;
  final ValueChanged<FileEntry>? onHoverEnter;
  final VoidCallback? onHoverExit;
  final bool selected;
  final bool selecting;
  final Uint8List? thumbnail;

  const NexaFileGridTile({
    super.key,
    required this.entry,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.onHoverEnter,
    this.onHoverExit,
    this.selected = false,
    this.selecting = false,
    this.thumbnail,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasPreview = thumbnail != null;
    final details = NexaFileTile._metadata(context, entry);

    return Semantics(
      button: true,
      selected: selected,
      label: '${entry.name}, $details',
      hint: selecting
          ? 'Toggles selection'
          : 'Opens ${entry.isFolder ? 'folder' : 'file'}. Long press and drag to select several.',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap == null ? null : () => onTap!(entry),
          onLongPress: onLongPress,
          onSecondaryTap:
              onSecondaryTap == null ? null : () => onSecondaryTap!(entry),
          onHover: (hovering) {
            if (hovering) {
              onHoverEnter?.call(entry);
            } else {
              onHoverExit?.call();
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          AppDimens.radiusStandard,
                        ),
                        child: hasPreview
                            ? Image.memory(
                                thumbnail!,
                                fit: BoxFit.cover,
                                cacheWidth: _gridDecodeWidth(context).round(),
                                gaplessPlayback: true,
                                errorBuilder: (_, __, ___) =>
                                    _previewArtwork(context),
                              )
                            : _previewArtwork(context),
                      ),
                    ),
                    if (selected)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                AppDimens.radiusStandard,
                              ),
                              border: Border.all(
                                color: scheme.primary,
                                width: AppDimens.space1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (selecting)
                      Positioned(
                        top: AppDimens.space6,
                        right: AppDimens.space6,
                        child: _SelectionBadge(selected: selected),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppDimens.space10),
              Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.callout.copyWith(color: scheme.onSurface),
              ),
              const SizedBox(height: AppDimens.space2),
              Text(
                details,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.bodySmall.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _previewArtwork(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surface,
      child: Center(
        child: entry.isFolder
            ? NexaFileGlyph.folder(size: AppDimens.iconTile)
            : NexaFileGlyph(
                name: entry.name,
                type: entry.type,
                size: AppDimens.iconTile,
              ),
      ),
    );
  }
}

double _gridDecodeWidth(BuildContext context) =>
    200 * MediaQuery.devicePixelRatioOf(context);
