import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_dimensions.dart';
import 'app_motion.dart';
import 'app_shadows.dart';

/// Material 3 surface levels.
///   L0: canvas (`surface`)
///   L1: content cards (`surfaceContainerLow`)
///   L2: grouped panels (`surfaceContainer`)
///   L3: floating controls (`surfaceContainerHigh`)
///   L4: modal surfaces (`surfaceContainerHigh`, higher elevation)
enum NexaSurfaceLevel { background, surface, grouped, floating, modal }

/// The single NexaDrive surface primitive.
///
/// Material 3 separates surfaces with tonal roles, not translucency. Only
/// floating and modal levels carry elevation; interactive surfaces use the
/// Material state layer through [InkWell].
class NexaSurface extends StatelessWidget {
  final NexaSurfaceLevel level;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? radius;
  final Color? color;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry margin;

  /// Retained for source compatibility; tonal surfaces ignore it.
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fill = color ?? _resolveColor(level, scheme);
    final edge = radius ?? _radiusFor(level);
    final interactive = onTap != null || onLongPress != null;

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(edge),
    );

    Widget content = Material(
      color: fill,
      surfaceTintColor: Colors.transparent,
      elevation: _elevationFor(level),
      shadowColor: scheme.shadow,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: AnimatedContainer(
        duration: AppMotion.resolve(context, AppMotion.fast),
        curve: AppMotion.curveFor(context, AppMotion.standard),
        padding: padding,
        decoration: BoxDecoration(
          border: _borderFor(level, scheme),
        ),
        child: child,
      ),
    );

    if (interactive) {
      content = InkWell(
        borderRadius: BorderRadius.circular(edge),
        onTap: onTap,
        onLongPress: onLongPress,
        child: content,
      );
    }

    return Padding(padding: margin, child: content);
  }

  static Color _resolveColor(NexaSurfaceLevel level, ColorScheme scheme) =>
      switch (level) {
        NexaSurfaceLevel.background => scheme.surface,
        NexaSurfaceLevel.surface => scheme.surfaceContainerLow,
        NexaSurfaceLevel.grouped => scheme.surfaceContainer,
        NexaSurfaceLevel.floating => scheme.surfaceContainerHigh,
        NexaSurfaceLevel.modal => scheme.surfaceContainerHigh,
      };

  static double _radiusFor(NexaSurfaceLevel level) => switch (level) {
        NexaSurfaceLevel.background => 0,
        NexaSurfaceLevel.surface => AppDimens.radiusCard,
        NexaSurfaceLevel.grouped => AppDimens.radiusMedium,
        NexaSurfaceLevel.floating => AppDimens.radiusMedium,
        NexaSurfaceLevel.modal => AppDimens.radiusSheet,
      };

  static double _elevationFor(NexaSurfaceLevel level) => switch (level) {
        NexaSurfaceLevel.background ||
        NexaSurfaceLevel.surface ||
        NexaSurfaceLevel.grouped =>
          0,
        NexaSurfaceLevel.floating => AppDimens.elevationLevel3,
        NexaSurfaceLevel.modal => AppDimens.elevationLevel3,
      };

  static Border? _borderFor(NexaSurfaceLevel level, ColorScheme scheme) {
    if (level == NexaSurfaceLevel.grouped ||
        level == NexaSurfaceLevel.surface) {
      return Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5));
    }
    return null;
  }

  /// Exposed for tests that need the resolved tonal fill.
  static List<BoxShadow> shadowFor(
    NexaSurfaceLevel level,
    Brightness brightness,
  ) =>
      switch (level) {
        NexaSurfaceLevel.floating ||
        NexaSurfaceLevel.modal =>
          AppShadows.level3(brightness),
        _ => AppShadows.none,
      };
}

/// Resolves the surface fill color for a level and brightness.
Color nexaSurfaceColor(NexaSurfaceLevel level, Brightness brightness) {
  final scheme = AppColors.scheme(brightness);
  return switch (level) {
    NexaSurfaceLevel.background => scheme.surface,
    NexaSurfaceLevel.surface => scheme.surfaceContainerLow,
    NexaSurfaceLevel.grouped => scheme.surfaceContainer,
    NexaSurfaceLevel.floating => scheme.surfaceContainerHigh,
    NexaSurfaceLevel.modal => scheme.surfaceContainerHigh,
  };
}
