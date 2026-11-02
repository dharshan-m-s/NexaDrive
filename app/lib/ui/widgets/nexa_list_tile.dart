import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';

/// Standard list row with leading icon, title, subtitle, trailing.
class NexaListTile extends StatelessWidget {
  final IconData? leadingIcon;

  /// Alias for [leadingIcon].
  final IconData? icon;
  final Color? leadingIconColor;
  final Color? leadingBackgroundColor;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool enabled;
  final bool showChevron;
  final EdgeInsetsGeometry? contentPadding;
  final double? minHeight;

  const NexaListTile({
    super.key,
    this.leadingIcon,
    this.icon,
    this.leadingIconColor,
    this.leadingBackgroundColor,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.enabled = true,
    this.showChevron = true,
    this.contentPadding,
    this.minHeight,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final accent = AppColors.accentFor(brightness);
    final onAccent = AppColors.onAccentContainerFor(brightness);
    final resolvedIcon = leadingIcon ?? icon;

    Widget? leadingWidget = leading;
    if (leadingWidget == null && resolvedIcon != null) {
      leadingWidget = Container(
        width: AppDimens.iconTileLarge,
        height: AppDimens.iconTileLarge,
        decoration: BoxDecoration(
          color: leadingBackgroundColor ??
              (brightness == Brightness.dark
                  ? accent.withValues(alpha: 0.18)
                  : accent.withValues(alpha: 0.12)),
          borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
        ),
        child: Icon(
          resolvedIcon,
          size: AppDimens.iconMedium,
          color: leadingIconColor ?? accent,
        ),
      );
    }

    return ListTile(
      enabled: enabled,
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
      selectedTileColor: AppColors.accentContainerFor(brightness),
      minTileHeight: minHeight ?? AppDimens.listHeightLarge,
      leading: leadingWidget,
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyle.title1.copyWith(
          color: selected
              ? onAccent
              : (enabled
                  ? AppColors.labelPrimaryFor(brightness)
                  : AppColors.labelTertiaryFor(brightness)),
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.caption1.copyWith(
                color: AppColors.labelSecondaryFor(brightness),
              ),
            ),
      trailing: trailing ??
          (showChevron
              ? Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.labelTertiaryFor(brightness),
                  size: AppDimens.iconMedium,
                )
              : null),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
      ),
      contentPadding: contentPadding ??
          const EdgeInsets.symmetric(
            horizontal: AppDimens.pageMargin,
            vertical: AppDimens.space4,
          ),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Single row inside a grouped list (alias for NexaListTile in grouped context).
class NexaGroupTile extends NexaListTile {
  const NexaGroupTile({
    super.key,
    super.leadingIcon,
    super.leadingIconColor,
    super.leadingBackgroundColor,
    super.leading,
    required super.title,
    super.subtitle,
    super.trailing,
    super.onTap,
    super.onLongPress,
    super.selected,
    super.enabled,
    super.showChevron,
    super.contentPadding,
  });
}
