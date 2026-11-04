import 'dart:ui';
import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_dimensions.dart';
import 'app_motion.dart';
import 'app_shadows.dart';
// NexaSurface is a member of the Nexa* component library even though it lives
// beside the design tokens, so it reuses the library's press primitive.
import '../../ui/widgets/nexa_pressable.dart';

/// Surface hierarchy levels:
///   L0: Porcelain/graphite page canvas.
///   L1: Primary content plane.
///   L2: Grouped secondary plane.
///   L3: Floating/elevated transient surface.
///   L4: Modal overlay.
///
/// One UI-inspired tonal separation and corner language, with native iOS-style
/// press feedback and motion. Content planes stay clear; optical glass belongs
/// to the dedicated navigation and transient-control primitives.
enum NexaSurfaceLevel { background, surface, grouped, floating, modal }

/// The single NexaDrive surface primitive.
///
/// Every surface in NexaDrive is one of these five levels rendered from the
/// semantic tokens — tonal separation first, a restrained shadow second, and
/// optional blur only for floating/modal contexts. This is the base the
/// grouped lists, panels, sheets and control clusters are built from.
class NexaSurface extends StatelessWidget {
  final NexaSurfaceLevel level;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? radius;
  final Color? color;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry margin;
  final bool useBlur;

  const NexaSurface({
    super.key,
    this.level = NexaSurfaceLevel.surface,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius,
    this.color,
    this.onTap,
    this.onLongPress,
    this.margin = EdgeInsets.zero,
    this.useBlur = false,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final fill = color ?? _resolveColor(level, brightness);
    final edge = radius ?? _radiusFor(level);
    final interactive = onTap != null || onLongPress != null;

    final decoration = BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(edge),
      boxShadow: _shadowFor(level, brightness),
      border: _borderFor(level, brightness),
    );

    Widget content = AnimatedContainer(
      duration: AppMotion.resolve(context, AppMotion.fast),
      curve: AppMotion.curveFor(context, AppMotion.standardCurve),
      margin: margin,
      padding: padding,
      decoration: decoration,
      child: child,
    );

    if (useBlur &&
        (level == NexaSurfaceLevel.floating ||
            level == NexaSurfaceLevel.modal)) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(edge),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: AppDimens.blurStandard,
            sigmaY: AppDimens.blurStandard,
          ),
          child: content,
        ),
      );
    }

    if (interactive) {
      // Spring-scaled press with a tonal wash instead of the (globally
      // disabled) Material ripple.
      content = NexaPressable(
        tintColor:
            AppColors.labelPrimaryFor(brightness).withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(edge),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(edge),
            onTap: onTap,
            onLongPress: onLongPress,
            child: content,
          ),
        ),
      );
    }

    return content;
  }

  static Color _resolveColor(NexaSurfaceLevel level, Brightness brightness) {
    switch (level) {
      case NexaSurfaceLevel.background:
        return AppColors.backgroundFor(brightness);
      case NexaSurfaceLevel.surface:
        return AppColors.surfaceFor(brightness);
      case NexaSurfaceLevel.grouped:
        return AppColors.surfaceGroupedFor(brightness);
      case NexaSurfaceLevel.floating:
        return AppColors.surfaceFor(brightness).withValues(
          alpha: brightness == Brightness.dark ? 0.94 : 0.96,
        );
      case NexaSurfaceLevel.modal:
        return AppColors.surfaceFor(brightness);
    }
  }

  static double _radiusFor(NexaSurfaceLevel level) => switch (level) {
        NexaSurfaceLevel.background => 0,
        NexaSurfaceLevel.surface => AppDimens.radiusMedium,
        NexaSurfaceLevel.grouped => AppDimens.radiusLarge,
        NexaSurfaceLevel.floating => AppDimens.radiusLarge,
        NexaSurfaceLevel.modal => AppDimens.radiusXLarge,
      };

  static List<BoxShadow> _shadowFor(
      NexaSurfaceLevel level, Brightness brightness) {
    switch (level) {
      case NexaSurfaceLevel.background:
      case NexaSurfaceLevel.surface:
      case NexaSurfaceLevel.grouped:
        return AppShadows.none;
      case NexaSurfaceLevel.floating:
        return AppShadows.level3(brightness);
      case NexaSurfaceLevel.modal:
        return AppShadows.level4(brightness);
    }
  }

  static Border? _borderFor(NexaSurfaceLevel level, Brightness brightness) {
    if (level == NexaSurfaceLevel.grouped ||
        level == NexaSurfaceLevel.surface) {
      return Border.all(
        color: AppColors.separatorFor(brightness).withValues(
          alpha: brightness == Brightness.dark ? 0.78 : 0.62,
        ),
        width: 0.55,
      );
    }
    if (level == NexaSurfaceLevel.floating) {
      return Border.all(
        color: brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.075)
            : Colors.black.withValues(alpha: 0.045),
        width: 0.6,
      );
    }
    return null;
  }
}

/// Resolves the surface fill color for a level and brightness.
Color nexaSurfaceColor(NexaSurfaceLevel level, Brightness brightness) {
  switch (level) {
    case NexaSurfaceLevel.background:
      return AppColors.backgroundFor(brightness);
    case NexaSurfaceLevel.surface:
      return AppColors.surfaceFor(brightness);
    case NexaSurfaceLevel.grouped:
      return AppColors.surfaceGroupedFor(brightness);
    case NexaSurfaceLevel.floating:
      return AppColors.surfaceFor(brightness).withValues(alpha: 0.82);
    case NexaSurfaceLevel.modal:
      return AppColors.surfaceFor(brightness);
  }
}
