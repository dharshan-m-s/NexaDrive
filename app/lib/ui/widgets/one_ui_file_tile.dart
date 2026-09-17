import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';
import '../../core/models/file_entry.dart';
import '../../core/utils/file_kind.dart';
import '../../core/utils/format.dart';

/// One UI file browser row. Icon tile + name + metadata + selection affordance.
class OneUiFileTile extends StatelessWidget {
  final FileEntry entry;
  final ValueChanged<FileEntry>? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool selecting;
  final Widget? trailing;
  final String? subtitle;
  final bool showChevron;

  /// Server-generated preview bytes for image files. Null falls back to the
  /// category icon, so the row is never empty while a thumbnail loads.
  final Uint8List? thumbnail;

  const OneUiFileTile({
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

    final Widget? leading;
    if (category == Category.image) {
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
        borderRadius: BorderRadius.circular(AppDimens.radiusTile),
        side: selected
            ? BorderSide(color: onAccent, width: 1.5)
            : BorderSide.none,
      ),
      leading: selecting
          ? _SelectionBadge(
              selected: selected,
              accent: brightness == Brightness.dark
                  ? AppColors.accentDark
                  : AppColors.accent,
            )
          : leading,
      title: Text(
        entry.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyle.rowTitle.copyWith(
          color: selected
              ? onAccent
              : AppColors.textPrimaryFor(brightness),
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle ?? defaultSubtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyle.caption
            .copyWith(color: AppColors.textSecondaryFor(brightness)),
      ),
      trailing: trailing ??
          (entry.type == 'folder' && showChevron
              ? Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textTertiaryFor(brightness),
                )
              : null),
    );
  }
}

/// Soft rounded icon tile matching One UI file icons.
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
        borderRadius: BorderRadius.circular(AppDimens.radiusInner),
      ),
      child: Icon(
        FileKind.icon(category),
        size: AppDimens.iconMedium,
        color: FileKind.tint(category, brightness),
      ),
    );
  }
}

/// Decode budget for a list-row preview. A 48dp tile on a 3x screen needs 144
/// physical pixels; decoding anything larger just wastes memory.
double _leadingDecodeWidth(BuildContext context) =>
    AppDimens.iconTileLarge * MediaQuery.devicePixelRatioOf(context);

/// Image preview tile: the real server thumbnail when available, otherwise the
/// category icon on a neutral tile.
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
    final radius = BorderRadius.circular(AppDimens.radiusInner);
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
            ? AppColors.surfaceAltDark
            : AppColors.surfaceAltLight,
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

/// Selection circle/check.
class _SelectionBadge extends StatelessWidget {
  final bool selected;
  final Color accent;
  const _SelectionBadge({required this.selected, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Icon(
      selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
      color: selected ? accent : AppColors.textTertiaryFor(Theme.of(context).brightness),
      size: 22,
    );
  }
}

/// Grid cells are bounded by the grid delegate; decode a little above the
/// tile size so the preview stays crisp without holding full-resolution pixels.
double _gridDecodeWidth(BuildContext context) =>
    170 * MediaQuery.devicePixelRatioOf(context);

/// Grid tile for the Files grid view.
class OneUiFileGridTile extends StatelessWidget {
  final FileEntry entry;
  final ValueChanged<FileEntry>? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool selecting;

  /// Server-generated preview bytes for image files.
  final Uint8List? thumbnail;

  const OneUiFileGridTile({
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
        borderRadius: BorderRadius.circular(AppDimens.radiusTile),
        onTap: onTap == null ? null : () => onTap!(entry),
        onLongPress: onLongPress,
        child: Container(
          decoration: BoxDecoration(
            color: brightness == Brightness.dark
                ? AppColors.surfaceDark
                : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(AppDimens.radiusTile),
            border: selected
                ? Border.all(color: AppColors.onAccentContainerFor(brightness), width: 1.8)
                : Border.all(color: Colors.transparent, width: 1.8),
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
                          : AppColors.textTertiaryFor(brightness),
                      size: 20,
                    ),
                ],
              ),
              const Spacer(),
              Text(
                entry.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.rowSubtitle.copyWith(
                  color: AppColors.textPrimaryFor(brightness),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: AppDimens.space2),
              Text(
                entry.isFolder ? 'Folder' : Format.bytes(entry.size),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.micro
                    .copyWith(color: AppColors.textSecondaryFor(brightness)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}