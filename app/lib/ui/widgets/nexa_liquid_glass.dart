import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';

/// Reusable, theme-aware translucent material for high-level app chrome.
///
/// Apply selectively to navigation, compact toolbars and transient controls.
/// The backdrop filter is clipped to the surface; ordinary content cards should
/// remain opaque and unblurred. High-contrast mode falls back to an opaque fill.
class NexaLiquidGlass extends StatelessWidget {
  final Widget child;
  final BorderRadiusGeometry borderRadius;
  final EdgeInsetsGeometry padding;
  final double blurSigma;
  final bool enabled;
  final bool forceOpaque;
  final bool showHighlight;
  final bool showShadow;

  const NexaLiquidGlass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(
      Radius.circular(AppDimens.radiusMedium),
    ),
    this.padding = const EdgeInsets.all(AppDimens.space12),
    this.blurSigma = 14,
    this.enabled = true,
    this.forceOpaque = false,
    this.showHighlight = true,
    this.showShadow = true,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final highContrast =
        forceOpaque || (MediaQuery.maybeOf(context)?.highContrast ?? false);
    final blurEnabled = enabled && !highContrast;
    final tint = AppColors.glassSurfaceFor(brightness);
    final highlight = AppColors.glassHighlightFor(brightness);
    final edge = AppColors.glassBorderFor(brightness);
    final opacity = highContrast
        ? 0.98
        : brightness == Brightness.dark
            ? 0.78
            : 0.70;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: AppColors.shadowColorFor(brightness).withValues(
                    alpha: brightness == Brightness.dark ? 0.72 : 0.88,
                  ),
                  blurRadius: 26,
                  spreadRadius: -4,
                  offset: const Offset(0, 10),
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
            if (blurEnabled)
              Positioned.fill(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(
                    sigmaX: blurSigma,
                    sigmaY: blurSigma,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      tint.withValues(alpha: opacity),
                      tint.withValues(alpha: (opacity + 0.08).clamp(0.0, 1.0)),
                    ],
                  ),
                ),
              ),
            ),
            Padding(padding: padding, child: child),
            if (showHighlight)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        stops: const [0, 0.42, 1],
                        colors: [
                          highlight.withValues(
                              alpha: highContrast ? 0.10 : 0.72),
                          Colors.transparent,
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: borderRadius,
                    border: Border.all(
                      color: edge.withValues(alpha: highContrast ? 0.95 : 0.82),
                      width: 0.75,
                    ),
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
