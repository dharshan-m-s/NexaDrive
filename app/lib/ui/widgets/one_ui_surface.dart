import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_motion.dart';
import '../../core/design/app_shadows.dart';

/// Surface-hierarchy levels (One UI doctrine):
///   L0 page background · L1 primary content surface · L2 grouped/list surface
///   L3 floating control / bottom sheet · L4 dialog / high-priority overlay.
enum OneUiSurfaceLevel { background, surface, group, floating, modal }

/// The single One UI surface primitive.
///
/// Every surface in NexaDrive (heroes, focus blocks, lists, sheets, dialogs,
/// bars) is one of these five levels rendered from theme tokens — tonal
/// separation first, restrained shadow second, blur only at L3+ floating.
class OneUiSurface extends StatelessWidget {
  final OneUiSurfaceLevel level;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? radius;
  final Color? color;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry margin;

  const OneUiSurface({
    super.key,
    this.level = OneUiSurfaceLevel.surface,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius,
    this.color,
    this.onTap,
    this.onLongPress,
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final fill = color ?? oneUiSurfaceColor(level, brightness);
    final edge = radius ?? _radiusFor(level);

    final decoration = BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(edge),
      boxShadow: _shadowFor(level, brightness),
    );

    return AnimatedContainer(
      duration: AppMotion.resolve(context, AppMotion.fast),
      curve: AppMotion.standard,
      margin: margin,
      padding: padding,
      decoration: decoration,
      child: onTap == null && onLongPress == null
          ? child
          : Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(edge),
                onTap: onTap,
                onLongPress: onLongPress,
                child: child,
              ),
            ),
    );
  }

  static double _radiusFor(OneUiSurfaceLevel l) => switch (l) {
        OneUiSurfaceLevel.background => 0,
        OneUiSurfaceLevel.surface => AppDimens.radiusCard,
        OneUiSurfaceLevel.group => AppDimens.radiusTile,
        OneUiSurfaceLevel.floating => AppDimens.radiusCard,
        OneUiSurfaceLevel.modal => AppDimens.radiusSheet,
      };

  static List<BoxShadow> _shadowFor(OneUiSurfaceLevel l, Brightness b) {
    if (l == OneUiSurfaceLevel.background) return AppShadows.none;
    if (l == OneUiSurfaceLevel.surface || l == OneUiSurfaceLevel.group) {
      return AppShadows.level1(b);
    }
    if (l == OneUiSurfaceLevel.floating) return AppShadows.level3(b);
    return AppShadows.level4(b);
  }
}

/// Resolves the surface fill color for a level and brightness.
Color oneUiSurfaceColor(OneUiSurfaceLevel level, Brightness brightness) {
  switch (level) {
    case OneUiSurfaceLevel.background:
      return brightness == Brightness.dark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight;
    case OneUiSurfaceLevel.surface:
      return brightness == Brightness.dark
          ? AppColors.surfaceDark
          : AppColors.surfaceLight;
    case OneUiSurfaceLevel.group:
      return brightness == Brightness.dark
          ? AppColors.surfaceAltDark
          : AppColors.surfaceAltLight;
    case OneUiSurfaceLevel.floating:
      return brightness == Brightness.dark
          ? AppColors.surfaceElevatedDark
          : AppColors.surfaceElevatedLight;
    case OneUiSurfaceLevel.modal:
      return brightness == Brightness.dark
          ? AppColors.surfaceDark
          : AppColors.surfaceLight;
  }
}