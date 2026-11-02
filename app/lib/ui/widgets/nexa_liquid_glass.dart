import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';

/// A bounded, translucent glass surface over the live scene.
///
/// The rounded clip is deliberately outside BackdropFilter: Flutter then
/// filters only the pixels visible through this surface, not the whole route.
/// Keep the tint light enough for the page to remain visible underneath.
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

  const NexaLiquidGlass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(
      Radius.circular(AppDimens.radiusMedium),
    ),
    this.padding = const EdgeInsets.all(AppDimens.space12),
    this.blurSigma = 18,
    this.enabled = true,
    this.forceOpaque = false,
    this.showHighlight = true,
    this.showShadow = true,
    this.tintOpacity,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final highContrast = MediaQuery.maybeOf(context)?.highContrast ?? false;
    final opaque = forceOpaque || highContrast || !enabled;
    final dark = brightness == Brightness.dark;
    final tint = AppColors.glassSurfaceFor(brightness);
    final tintAlpha =
        (tintOpacity ?? (dark ? 0.14 : 0.105)).clamp(0.0, 0.24).toDouble();
    final edge = dark
        ? Colors.white.withValues(alpha: 0.24)
        : Colors.white.withValues(alpha: 0.72);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.28 : 0.10),
                  blurRadius: 28,
                  spreadRadius: -9,
                  offset: const Offset(0, 12),
                ),
              ]
            : const [],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            if (!opaque)
              Positioned.fill(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(
                    sigmaX: blurSigma.clamp(0.0, 24.0).toDouble(),
                    sigmaY: blurSigma.clamp(0.0, 24.0).toDouble(),
                  ),
                  blendMode: BlendMode.srcOver,
                  child: const SizedBox.expand(),
                ),
              ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: opaque
                      ? AppColors.surfaceFor(brightness)
                      : tint.withValues(alpha: tintAlpha),
                ),
              ),
            ),
            if (!opaque && showHighlight)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: dark
                            ? [
                                Colors.white.withValues(alpha: 0.105),
                                Colors.white.withValues(alpha: 0.018),
                                Colors.black.withValues(alpha: 0.045),
                              ]
                            : [
                                Colors.white.withValues(alpha: 0.32),
                                Colors.white.withValues(alpha: 0.055),
                                const Color(0xFF7770A8)
                                    .withValues(alpha: 0.025),
                              ],
                        stops: const [0, 0.42, 1],
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: padding,
              child: Material(
                type: MaterialType.transparency,
                child: child,
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: borderRadius,
                    border: Border.all(color: edge, width: 0.8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
