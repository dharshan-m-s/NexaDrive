import 'package:flutter/material.dart';

import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import 'glass_engine/glass_params.dart';
import 'glass_engine/glass_surface.dart';

/// Shared NexaDrive optical-glass material.
///
/// Rendering is based on the Apache-2.0 flutter_liquid_glasses 0.1.3
/// implementation of Kyant's AndroidLiquidGlass optics: signed-distance-field
/// refraction, seven-path chromatic dispersion, a separate directional
/// specular pass and an isolated inner-shadow pass. Screens only configure
/// the optical profile; shader lifetime and renderer compatibility stay here.
class NexaLiquidGlass extends StatelessWidget {
  final Widget child;
  final BorderRadiusGeometry borderRadius;
  final EdgeInsetsGeometry padding;
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
  })  : assert(refractionHeight >= 0),
        assert(depthEffect >= 0 && depthEffect <= 1.5),
        assert(chromaticDispersion >= 0 && chromaticDispersion <= 3);

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final dark = brightness == Brightness.dark;
    final highContrast = MediaQuery.maybeOf(context)?.highContrast ?? false;
    final reduceTransparency = forceOpaque || highContrast || !enabled;
    final tintAlpha =
        (tintOpacity ?? (dark ? 0.10 : 0.075)).clamp(0.0, 0.36).toDouble();
    final tint = AppColors.glassSurfaceFor(brightness);
    final accent = AppColors.accentFor(brightness);
    final radius = borderRadius.resolve(Directionality.of(context));

    final params = GlassParams(
      // The current NexaDrive chrome uses uniform rounded corners. The engine
      // clamps the radius against the actual paint bounds before setting SDF.
      cornerRadius: radius.topLeft.x,
      refractionHeight: refractionHeight,
      refractionAmount: refractionAmount,
      depthEffect: depthEffect,
      chromatic: chromaticDispersion,
      saturation: dark ? 1.42 : 1.28,
      brightness: 0,
      contrast: 1.02,
      tintColor: [
        accent.r,
        accent.g,
        accent.b,
        tintAlpha * 0.28,
      ],
      surfaceColor: [
        tint.r,
        tint.g,
        tint.b,
        tintAlpha,
      ],
      highlightColor: const [1.0, 1.0, 1.0],
      highlightAngle: 0.785398,
      highlightFalloff: 0.9,
      highlightAlpha: showHighlight ? (dark ? 0.48 : 0.62) : 0,
      highlightStroke: showHighlight ? 1.35 : 0,
      highlightBlur: showHighlight ? 0.35 : 0,
      shadowColor: const [0.0, 0.0, 0.0],
      shadowAlpha: showHighlight ? 0.14 : 0,
      shadowOffsetX: 0,
      shadowOffsetY: 1,
      shadowBlur: 3,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.34 : 0.10),
                  blurRadius: 28,
                  spreadRadius: -8,
                  offset: const Offset(0, 12),
                ),
              ]
            : const [],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: GlassSurface(
          params: params,
          blurSigma: blurSigma,
          reduceTransparency: reduceTransparency,
          fallbackColor: AppColors.surfaceFor(brightness),
          child: Padding(
            padding: padding,
            child: Material(
              type: MaterialType.transparency,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
