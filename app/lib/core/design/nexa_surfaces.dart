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
class NexaSurface extends StatefulWidget {
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
  State<NexaSurface> createState() => _NexaSurfaceState();
}

class _NexaSurfaceState extends State<NexaSurface> {
  bool _pressed = false;

  @override
  void didUpdateWidget(covariant NexaSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onTap == null && widget.onLongPress == null && _pressed) {
      _pressed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final baseFill = widget.color ?? _resolveColor(widget.level, brightness);
    final fill = _pressed
        ? Color.alphaBlend(
            AppColors.labelPrimaryFor(brightness).withValues(alpha: 0.035),
            baseFill,
          )
        : baseFill;
    final edge = widget.radius ?? _radiusFor(widget.level);
    final interactive = widget.onTap != null || widget.onLongPress != null;

    final decoration = BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(edge),
      boxShadow: _shadowFor(widget.level, brightness),
      border: _borderFor(widget.level, brightness),
    );

    Widget content = AnimatedContainer(
      duration: AppMotion.resolve(context, AppMotion.fast),
      curve: AppMotion.curveFor(context, AppMotion.standardCurve),
      margin: widget.margin,
      padding: widget.padding,
      decoration: decoration,
      child: widget.child,
    );

    if (widget.useBlur &&
        (widget.level == NexaSurfaceLevel.floating ||
            widget.level == NexaSurfaceLevel.modal)) {
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
      content = Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(edge),
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onHighlightChanged: (value) {
            if (_pressed != value) setState(() => _pressed = value);
          },
          child: AnimatedScale(
            scale: _pressed ? 0.985 : 1,
            duration: AppMotion.resolve(context, AppMotion.micro),
            curve: AppMotion.curveFor(context, AppMotion.standardCurve),
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

  static List<BoxShadow> _shadowFor(NexaSurfaceLevel level, Brightness brightness) {
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
    if (level == NexaSurfaceLevel.grouped || level == NexaSurfaceLevel.surface) {
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
