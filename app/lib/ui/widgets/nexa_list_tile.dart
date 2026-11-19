import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';

/// Standard Material 3 list row with leading icon, title, subtitle, trailing.
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

  static Color _semanticTint(
    IconData? icon,
    Color fallback,
    Brightness brightness,
  ) {
    if (icon == Icons.notifications_outlined ||
        icon == Icons.notifications_rounded ||
        icon == Icons.schedule_rounded) {
      return AppColors.warningFor(brightness);
    }
    if (icon == Icons.delete_outline_rounded ||
        icon == Icons.delete_rounded ||
        icon == Icons.logout_rounded) {
      return AppColors.errorFor(brightness);
    }
    if (icon == Icons.check_circle_outline_rounded ||
        icon == Icons.verified_user_outlined ||
        icon == Icons.lock_outline_rounded) {
      return AppColors.successFor(brightness);
    }
    if (icon == Icons.sync_rounded ||
        icon == Icons.cloud_upload_outlined ||
        icon == Icons.cloud_done_outlined) {
      return AppColors.infoFor(brightness);
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = scheme.brightness;
    final resolvedIcon = leadingIcon ?? icon;

    Widget? leadingWidget = leading;
    if (leadingWidget == null && resolvedIcon != null) {
      final tint = leadingIconColor ??
          _semanticTint(resolvedIcon, scheme.primary, brightness);
      final background = leadingBackgroundColor ??
          tint.withValues(alpha: brightness == Brightness.dark ? 0.20 : 0.12);
      leadingWidget = Container(
        width: AppDimens.iconTileLarge,
        height: AppDimens.iconTileLarge,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
        ),
        child: Icon(
          resolvedIcon,
          size: AppDimens.iconMedium,
          color: tint,
        ),
      );
    }

    final foreground = !enabled
        ? scheme.onSurface.withValues(alpha: 0.38)
        : selected
            ? scheme.onSecondaryContainer
            : scheme.onSurface;

    return ListTile(
      enabled: enabled,
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
      selectedTileColor: scheme.secondaryContainer,
      minTileHeight: minHeight ?? AppDimens.listHeight,
      leading: leadingWidget,
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyle.titleMedium.copyWith(color: foreground),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.bodyMedium.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
      trailing: trailing ??
          (showChevron
              ? Icon(
                  Icons.chevron_right_rounded,
                  color: scheme.onSurfaceVariant,
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
