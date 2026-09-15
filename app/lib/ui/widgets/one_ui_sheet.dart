import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';

/// Opens a One UI modal sheet using the theme's sheet surface and motion.
///
/// One UI sheets arrive with restrained motion, keep the 28dp top radius, are
/// drag-dismissible, and dim the page the standard amount.
Future<T?> showOneUiSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool isDismissible = true,
  bool enableDrag = true,
  Color? barrierColor,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    barrierColor: barrierColor ?? AppColors.scrim,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (context) => builder(context),
  );
}

/// Standard One UI sheet header: title (and optional subtitle) above content.
class OneUiSheetHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const OneUiSheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.space8,
        AppDimens.space8,
        AppDimens.space8,
        AppDimens.space16,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyle.sectionHeader.copyWith(
                    color: AppColors.textPrimaryFor(brightness),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: AppDimens.space4),
                  Text(
                    subtitle!,
                    style: AppTextStyle.caption.copyWith(
                      color: AppColors.textSecondaryFor(brightness),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Wraps sheet content in the One UI sheet chrome (radius, color, paddings).
class OneUiSheetBody extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const OneUiSheetBody({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(
      AppDimens.pageMargin, 0, AppDimens.pageMargin, AppDimens.space16,
    ),
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final surface = brightness == Brightness.dark
        ? AppColors.surfaceDark
        : AppColors.surfaceLight;

    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppDimens.radiusSheet),
        ),
        child: Material(
          color: surface,
          child: SingleChildScrollView(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A sheet action row — icon tile + label, min 56dp tall.
class OneUiSheetAction extends StatelessWidget {
  final IconData icon;
  final Color? tint;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool destructive;
  final bool enabled;

  const OneUiSheetAction({
    super.key,
    required this.icon,
    this.tint,
    required this.title,
    this.subtitle,
    this.onTap,
    this.destructive = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final color = destructive
        ? AppColors.errorFor(brightness)
        : (tint ?? AppColors.accentTextFor(brightness));

    return ListTile(
      enabled: enabled,
      onTap: enabled ? onTap : null,
      minTileHeight: AppDimens.listHeight,
      leading: Container(
        width: AppDimens.iconTileLarge,
        height: AppDimens.iconTileLarge,
        decoration: BoxDecoration(
          color: destructive
              ? AppColors.errorContainerFor(brightness)
              : AppColors.accentSubtleFor(brightness),
          borderRadius: BorderRadius.circular(AppDimens.radiusInner),
        ),
        child: Icon(icon, color: color, size: AppDimens.iconMedium),
      ),
      title: Text(
        title,
        style: AppTextStyle.rowTitle.copyWith(
          color: AppColors.textPrimaryFor(brightness),
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: AppTextStyle.caption.copyWith(
                color: AppColors.textSecondaryFor(brightness),
              ),
            ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusTile),
      ),
    );
  }
}