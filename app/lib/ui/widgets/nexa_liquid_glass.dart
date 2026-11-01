import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';

/// A refractive material for the app's navigation and transient chrome.
///
/// On Impeller, the backdrop is processed by a GPU fragment shader: the
/// background is sampled with a small optical displacement, subtle channel
/// separation and a restrained edge Fresnel. Other renderers use a clipped
/// blur fallback rather than attempting an unsupported image-filter shader.
class NexaLiquidGlass extends StatefulWidget {
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
  State<NexaLiquidGlass> createState() => _NexaLiquidGlassState();
}

class _NexaLiquidGlassState extends State<NexaLiquidGlass> {
  ui.FragmentShader? _glassShader;

  @override
  void initState() {
    super.initState();
    _loadGlassShader();
  }

  Future<void> _loadGlassShader() async {
    if (!widget.enabled || !ui.ImageFilter.isShaderFilterSupported) return;
    try {
      final program = await ui.FragmentProgram.fromAsset(
        'shaders/nexa_liquid_glass.frag',
      );
      final shader = program.fragmentShader();
      if (!mounted) {
        shader.dispose();
        return;
      }
      setState(() => _glassShader = shader);
    } catch (_) {
      // Shader compilation/loading can fail on a device-specific backend.
      // The clipped blur path below remains a fully supported fallback.
    }
  }

  @override
  void dispose() {
    _glassShader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final highContrast = widget.forceOpaque ||
        (MediaQuery.maybeOf(context)?.highContrast ?? false);
    final filterEnabled = widget.enabled && !highContrast;
    final tint = AppColors.glassSurfaceFor(brightness);
    final highlight = AppColors.glassHighlightFor(brightness);
    final edge = AppColors.glassBorderFor(brightness);
    final tintOpacity = highContrast
        ? 0.98
        : brightness == Brightness.dark
            ? 0.20
            : 0.15;
    final shader = _glassShader;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius,
        boxShadow: widget.showShadow
            ? [
                BoxShadow(
                  color: AppColors.shadowColorFor(brightness).withValues(
                    alpha: brightness == Brightness.dark ? 0.62 : 0.72,
                  ),
                  blurRadius: 24,
                  spreadRadius: -5,
                  offset: const Offset(0, 9),
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
            if (filterEnabled)
              Positioned.fill(
                child: BackdropFilter(
                  filter: shader != null
                      ? ui.ImageFilter.shader(shader)
                      : ui.ImageFilter.blur(
                          sigmaX: widget.blurSigma,
                          sigmaY: widget.blurSigma,
                        ),
                  child: const SizedBox.expand(),
                ),
              ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: tintOpacity),
                ),
              ),
            ),
            Padding(padding: widget.padding, child: widget.child),
            if (widget.showHighlight)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        stops: const [0, 0.22, 0.62],
                        colors: [
                          highlight.withValues(
                            alpha: highContrast ? 0.10 : 0.24,
                          ),
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
                    borderRadius: widget.borderRadius,
                    border: Border.all(
                      color: edge.withValues(alpha: highContrast ? 0.95 : 0.70),
                      width: 0.8,
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
