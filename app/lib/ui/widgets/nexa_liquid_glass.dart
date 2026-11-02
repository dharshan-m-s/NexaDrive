import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';

/// A clipped optical glass material for navigation and transient controls.
///
/// Impeller applies a custom refraction shader directly to the live backdrop.
/// The centre remains sharp; only the edge bends and separates colour. Other
/// renderers use a deliberately restrained blur rather than pretending to
/// reproduce the optical shader.
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
    this.blurSigma = 1.8,
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
  bool _loadingShader = false;

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
    if (!widget.enabled ||
        _loadingShader ||
        !ui.ImageFilter.isShaderFilterSupported) {
      return;
    }

    _loadingShader = true;
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
      // The restrained renderer-specific fallback remains functional.
    } finally {
      _loadingShader = false;
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
    final highContrast = MediaQuery.maybeOf(context)?.highContrast ?? false;
    final opaque = widget.forceOpaque || highContrast || !widget.enabled;
    final active = !opaque;
    final dark = brightness == Brightness.dark;
    final tint = AppColors.glassSurfaceFor(brightness);
    final tintAlpha = (widget.tintOpacity ?? (dark ? 0.105 : 0.07))
        .clamp(0.0, 0.20)
        .toDouble();
    final edge = dark
        ? Colors.white.withValues(alpha: 0.19)
        : Colors.white.withValues(alpha: 0.58);
    final shader = active ? _shader : null;

    if (shader != null) {
      // ImageFilter shaders receive u_size automatically at float indices 0-1.
      // The following vec4 contains the actual clipped corner radii in pixels.
      final radii = widget.borderRadius.resolve(Directionality.of(context));
      final scale = MediaQuery.devicePixelRatioOf(context);
      shader
        ..setFloat(2, radii.topLeft.x * scale)
        ..setFloat(3, radii.topRight.x * scale)
        ..setFloat(4, radii.bottomRight.x * scale)
        ..setFloat(5, radii.bottomLeft.x * scale);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius,
        boxShadow: widget.showShadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.25 : 0.075),
                  blurRadius: 25,
                  spreadRadius: -10,
                  offset: const Offset(0, 10),
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
            if (active)
              Positioned.fill(
                child: BackdropFilter(
                  filter: shader != null
                      ? ui.ImageFilter.compose(
                          // Blur the live backdrop first, then refract that
                          // texture with the GPU shader. The edge is optically
                          // displaced; this is not a transparent tint layer.
                          outer: ui.ImageFilter.shader(shader),
                          inner: ui.ImageFilter.blur(
                            sigmaX: widget.blurSigma.clamp(0.0, 2.4).toDouble(),
                            sigmaY: widget.blurSigma.clamp(0.0, 2.4).toDouble(),
                          ),
                        )
                      : ui.ImageFilter.blur(
                          // Older/unsupported renderers keep a modest frosted
                          // fallback. Impeller uses the refractive shader path.
                          sigmaX: widget.blurSigma.clamp(0.0, 4.0).toDouble(),
                          sigmaY: widget.blurSigma.clamp(0.0, 4.0).toDouble(),
                        ),
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
                                Colors.white.withValues(alpha: 0.055),
                                const Color(0xFF9A8CFF)
                                    .withValues(alpha: 0.035),
                                Colors.black.withValues(alpha: 0.025),
                              ]
                            : [
                                Colors.white.withValues(alpha: 0.12),
                                const Color(0xFF8A7CFF)
                                    .withValues(alpha: 0.035),
                                Colors.white.withValues(alpha: 0.012),
                              ],
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: widget.padding,
              child: Material(
                type: MaterialType.transparency,
                child: widget.child,
              ),
            ),
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
                        alpha: dark ? 0.11 : 0.20,
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
