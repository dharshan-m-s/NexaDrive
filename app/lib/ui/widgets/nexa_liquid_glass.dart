import 'package:flutter/material.dart';

import '../../core/design/app_dimensions.dart';

/// Compatibility surface wrapper.
///
/// The optical-glass material is gone. Every caller keeps its existing API,
/// but the result is now a Material 3 tonal surface with elevation. The
/// floating navigation pill uses this wrapper and retains its spring motion.
class NexaLiquidGlass extends StatelessWidget {
  final Widget child;
  final BorderRadiusGeometry borderRadius;
  final EdgeInsetsGeometry padding;

  /// Ignored: Material 3 surfaces are tonal and opaque.
  final double blurSigma;
  final bool enabled;
  final bool forceOpaque;
  final bool showHighlight;
  final bool showShadow;
  final double? tintOpacity;
  final double refractionHeight;
  final double refractionAmount;
  final double depthEffect;
  final double chromaticDispersion;

  const NexaLiquidGlass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(
      Radius.circular(AppDimens.radiusMedium),
    ),
    this.padding = const EdgeInsets.all(AppDimens.space12),
    this.blurSigma = 1.8,
    this.enabled = true,
    this.forceOpaque = false,
    this.showHighlight = true,
    this.showShadow = true,
    this.tintOpacity,
    this.refractionHeight = 20,
    this.refractionAmount = -38,
    this.depthEffect = 0.9,
    this.chromaticDispersion = 1.7,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      elevation: showShadow ? AppDimens.elevationLevel3 : 0,
      shadowColor: scheme.shadow,
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
  }
}
