import 'dart:ui';
import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_dimensions.dart';
import 'app_motion.dart';
import 'app_shadows.dart';

/// Surface hierarchy levels (Apple-inspired):
///   L0: Page background (systemGroupedBackground)
///   L1: Primary content surface (systemBackground)
///   L2: Grouped/secondary surface (secondarySystemGroupedBackground)
///   L3: Floating/elevated surface (popovers, sheets)
///   L4: Modal overlay (full-screen modals)
enum NexaSurfaceLevel { background, surface, grouped, floating, modal }

/// The single NexaDrive surface primitive.
///
/// Every surface in NexaDrive is one of these five levels rendered from the
/// semantic tokens — tonal separation first, a restrained shadow second, and a
/// backdrop blur only for the floating/modal levels. This is the base the
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

    final decoration = BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(edge),
      boxShadow: _shadowFor(level, brightness),
      border: _borderFor(level, brightness),
    );

    Widget content = AnimatedContainer(
      duration: AppMotion.resolve(context, AppMotion.fast),
      curve: AppMotion.standardCurve,
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

    if (onTap != null || onLongPress != null) {
      content = Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(edge),
          onTap: onTap,
          onLongPress: onLongPress,
          child: content,
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
        return AppColors.surfaceFor(brightness).withValues(alpha: 0.82);
      case NexaSurfaceLevel.modal:
        return AppColors.surfaceFor(brightness);
    }
  }

  static double _radiusFor(NexaSurfaceLevel l) => switch (l) {
        NexaSurfaceLevel.background => 0,
        NexaSurfaceLevel.surface => AppDimens.radiusMedium,
        NexaSurfaceLevel.grouped => AppDimens.radiusMedium,
        NexaSurfaceLevel.floating => AppDimens.radiusLarge,
        NexaSurfaceLevel.modal => AppDimens.radiusXLarge,
      };

  static List<BoxShadow> _shadowFor(NexaSurfaceLevel l, Brightness b) {
    switch (l) {
      case NexaSurfaceLevel.background:
      case NexaSurfaceLevel.surface:
      case NexaSurfaceLevel.grouped:
        // iOS content cards are flat; a hairline border carries dark mode.
        return AppShadows.none;
      case NexaSurfaceLevel.floating:
        return AppShadows.level3(b);
      case NexaSurfaceLevel.modal:
        return AppShadows.level4(b);
    }
  }

  static Border? _borderFor(NexaSurfaceLevel l, Brightness b) {
    if ((l == NexaSurfaceLevel.grouped || l == NexaSurfaceLevel.surface) &&
        b == Brightness.dark) {
      return Border.all(color: AppColors.separatorFor(b), width: 0.5);
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
