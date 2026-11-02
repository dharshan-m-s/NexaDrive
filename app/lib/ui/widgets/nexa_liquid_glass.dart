import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';

/// Live optical material for navigation and transient controls.
///
/// The clipped surface samples the page beneath it, softens that image, then
/// applies an Impeller refraction shader. Other renderers use a real backdrop
/// blur and restrained tint. Foreground content is painted after the material.
class NexaLiquidGlass extends StatefulWidget {
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
    this.blurSigma = 8,
    this.enabled = true,
    this.forceOpaque = false,
    this.showHighlight = true,
    this.showShadow = true,
    this.tintOpacity,
  });

  @override
  State<NexaLiquidGlass> createState() => _NexaLiquidGlassState();
}

class _NexaLiquidGlassState extends State<NexaLiquidGlass> {
  static Future<ui.FragmentProgram>? _program;
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    _loadShader();
  }

  @override
  void didUpdateWidget(covariant NexaLiquidGlass oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.enabled && widget.enabled && _shader == null) {
      _loadShader();
    }
  }

  Future<void> _loadShader() async {
    if (!widget.enabled || !ui.ImageFilter.isShaderFilterSupported) return;
    try {
      final program = await (_program ??= ui.FragmentProgram.fromAsset(
        'shaders/nexa_liquid_glass.frag',
      ));
      final shader = program.fragmentShader();
      if (!mounted) {
        shader.dispose();
        return;
      }
      setState(() => _shader = shader);
    } catch (_) {
      _program = null;
      // The renderer-specific blur fallback remains functional.
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final opaque = widget.forceOpaque ||
        (MediaQuery.maybeOf(context)?.highContrast ?? false);
    final active = widget.enabled && !opaque;
    final dark = brightness == Brightness.dark;
    final tint = AppColors.glassSurfaceFor(brightness);
    final tintAlpha = widget.tintOpacity ?? (dark ? 0.14 : 0.10);
    final edge = dark
        ? Colors.white.withValues(alpha: 0.13)
        : Colors.white.withValues(alpha: 0.48);
    final shader = _shader;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius,
        boxShadow: widget.showShadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.34 : 0.10),
                  blurRadius: 28,
                  spreadRadius: -9,
                  offset: const Offset(0, 12),
                ),
              ]
            : const [],
      ),
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: opaque
                      ? AppColors.surfaceFor(brightness)
                      : tint.withValues(alpha: tintAlpha),
                ),
              ),
            ),
            if (active)
              Positioned.fill(
                child: BackdropFilter(
                  filter: shader == null
                      ? ui.ImageFilter.blur(
                          sigmaX: widget.blurSigma,
                          sigmaY: widget.blurSigma,
                        )
                      : ui.ImageFilter.compose(
                          outer: ui.ImageFilter.shader(shader),
                          inner: ui.ImageFilter.blur(
                            sigmaX: widget.blurSigma,
                            sigmaY: widget.blurSigma,
                          ),
                        ),
                  child: const SizedBox.expand(),
                ),
              ),
            if (active)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: dark
                            ? [
                                Colors.white.withValues(alpha: 0.065),
                                const Color(0xFF9A8CFF)
                                    .withValues(alpha: 0.045),
                                Colors.black.withValues(alpha: 0.035),
                              ]
                            : [
                                Colors.white.withValues(alpha: 0.16),
                                const Color(0xFF8A7CFF)
                                    .withValues(alpha: 0.035),
                                Colors.white.withValues(alpha: 0.015),
                              ],
                      ),
                    ),
                  ),
                ),
              ),
            Padding(padding: widget.padding, child: widget.child),
            // The Impeller shader paints the directional Fresnel and
            // specular response itself. Only the non-shader fallback needs a
            // tiny top catch-light; never lay a broad white gradient over glass.
            if (widget.showHighlight && active && shader == null)
              Positioned(
                left: 1,
                right: 1,
                top: 0,
                child: IgnorePointer(
                  child: Container(
                    height: 1,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(
                        alpha: dark ? 0.075 : 0.18,
                      ),
                      borderRadius: widget.borderRadius,
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: widget.borderRadius,
                    border: Border.all(color: edge, width: 0.65),
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
