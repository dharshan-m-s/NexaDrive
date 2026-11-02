import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';
import '../../core/models/file_entry.dart';
import '../../core/utils/file_kind.dart';
import '../../core/utils/format.dart';

/// iOS-style file browser list tile.
class NexaFileTile extends StatelessWidget {
  final FileEntry entry;
  final ValueChanged<FileEntry>? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool selecting;
  final Widget? trailing;
  final String? subtitle;
  final bool showChevron;
  final Uint8List? thumbnail;

  const NexaFileTile({
    super.key,
    required this.entry,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.selecting = false,
    this.trailing,
    this.subtitle,
    this.showChevron = true,
    this.thumbnail,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final onAccent = AppColors.onAccentContainerFor(brightness);
    final category = entry.category;

    Widget? leading;
    if (selecting) {
      leading = _SelectionBadge(
        selected: selected,
        accent: AppColors.accentFor(brightness),
      );
    } else if (category == Category.image) {
      leading = _ImageThumb(
        entry: entry,
        bytes: thumbnail,
        decodeWidth: _leadingDecodeWidth(context),
      );
    } else {
      leading = _FileIconTile(category: category, brightness: brightness);
    }

    final defaultSubtitle = entry.isFolder
        ? 'Folder'
        : entry.size != null
            ? Format.bytes(entry.size)
            : 'File';

    return ListTile(
      onTap: onTap == null ? null : () => onTap!(entry),
      onLongPress: onLongPress,
      selected: selected,
      selectedTileColor: AppColors.accentContainerFor(brightness),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
        side: selected
            ? BorderSide(color: onAccent, width: 1.5)
            : BorderSide.none,
      ),
      leading: leading,
      title: Text(
        entry.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyle.title1.copyWith(
          color: selected ? onAccent : AppColors.labelPrimaryFor(brightness),
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      subtitle: Text(
        subtitle ?? defaultSubtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyle.caption1.copyWith(
          color: AppColors.labelSecondaryFor(brightness),
        ),
      ),
      trailing: trailing ??
          (entry.isFolder && showChevron
              ? Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.labelTertiaryFor(brightness),
                  size: AppDimens.iconMedium,
                )
              : null),
      minTileHeight: AppDimens.listHeightLarge,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppDimens.pageMargin,
        vertical: AppDimens.space4,
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}

double _leadingDecodeWidth(BuildContext context) =>
    AppDimens.iconTileLarge * MediaQuery.devicePixelRatioOf(context);

/// Soft rounded icon tile matching iOS file icons.
class _FileIconTile extends StatelessWidget {
  final Category category;
  final Brightness brightness;

  const _FileIconTile({required this.category, required this.brightness});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppDimens.iconTileLarge,
      height: AppDimens.iconTileLarge,
      decoration: BoxDecoration(
        color: FileKind.tileFill(category, brightness),
        borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
      ),
      child: Icon(
        FileKind.icon(category),
        size: AppDimens.iconMedium,
        color: FileKind.tint(category, brightness),
      ),
    );
  }
}

/// Image preview tile: real thumbnail or fallback.
class _ImageThumb extends StatelessWidget {
  final FileEntry entry;
  final Uint8List? bytes;
  final double decodeWidth;

  const _ImageThumb({
    required this.entry,
    this.bytes,
    required this.decodeWidth,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final radius = BorderRadius.circular(AppDimens.radiusStandard);
    final value = bytes;

    if (value != null) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.memory(
          value,
          width: AppDimens.iconTileLarge,
          height: AppDimens.iconTileLarge,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          cacheWidth: decodeWidth.round(),
          semanticLabel: 'Preview of ${entry.name}',
          errorBuilder: (context, _, __) => _fallback(brightness, radius),
        ),
      );
    }
    return _fallback(brightness, radius);
  }

  Widget _fallback(Brightness brightness, BorderRadius radius) {
    return Container(
      width: AppDimens.iconTileLarge,
      height: AppDimens.iconTileLarge,
      decoration: BoxDecoration(
        color: brightness == Brightness.dark
            ? AppColors.surfaceGroupedAltFor(brightness)
            : AppColors.fillFor(brightness),
        borderRadius: radius,
      ),
      child: Icon(
        Icons.image_rounded,
        size: AppDimens.iconMedium,
        color: FileKind.tint(Category.image, brightness),
      ),
    );
  }
}

/// Selection badge for multi-select mode.
class _SelectionBadge extends StatelessWidget {
  final bool selected;
  final Color accent;

  const _SelectionBadge({required this.selected, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Icon(
      selected
          ? Icons.check_circle_rounded
          : Icons.radio_button_unchecked_rounded,
      color: selected
          ? accent
          : AppColors.labelTertiaryFor(Theme.of(context).brightness),
      size: 22,
    );
  }
}

/// Decode budget for grid previews.
double _gridDecodeWidth(BuildContext context) =>
    170 * MediaQuery.devicePixelRatioOf(context);

/// Grid tile for the Files grid view.
class NexaFileGridTile extends StatelessWidget {
  final FileEntry entry;
  final ValueChanged<FileEntry>? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool selecting;
  final Uint8List? thumbnail;

  const NexaFileGridTile({
    super.key,
    required this.entry,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.selecting = false,
    this.thumbnail,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final accent = AppColors.accentFor(brightness);
    final category = entry.category;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
        onTap: onTap == null ? null : () => onTap!(entry),
        onLongPress: onLongPress,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceGroupedFor(brightness),
            borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
            border: selected
                ? Border.all(
                    color: AppColors.onAccentContainerFor(brightness), width: 2)
                : Border.all(color: Colors.transparent, width: 2),
          ),
          padding: const EdgeInsets.all(AppDimens.space12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (category == Category.image)
                    _ImageThumb(
                      entry: entry,
                      bytes: thumbnail,
                      decodeWidth: _gridDecodeWidth(context),
                    )
                  else
                    _FileIconTile(category: category, brightness: brightness),
                  if (selecting)
                    Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: selected
                          ? accent
                          : AppColors.labelTertiaryFor(brightness),
                      size: 20,
                    ),
                ],
              ),
              const Spacer(),
              Text(
                entry.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.caption1.copyWith(
                  color: AppColors.labelPrimaryFor(brightness),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: AppDimens.space2),
              Text(
                entry.isFolder ? 'Folder' : Format.bytes(entry.size),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.caption2.copyWith(
                  color: AppColors.labelSecondaryFor(brightness),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
