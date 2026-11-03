import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';

/// A bounded optical-glass surface over the live scene.
///
/// Impeller uses a GPU image-filter shader for real backdrop displacement and
/// curved-edge refraction. The blur-only path is a compatibility fallback.
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
    this.blurSigma = 6,
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
  static Future<ui.FragmentProgram>? _programFuture;

  ui.FragmentShader? _shader;
  bool _shaderFilterErrorReported = false;

  @override
  void initState() {
    super.initState();
    if (ui.ImageFilter.isShaderFilterSupported) {
      unawaited(_loadShader());
    } else {
      debugPrint(
        'NexaDrive glass: Impeller image-filter shaders are unavailable; '
        'using compatibility blur.',
      );
    }
  }

  Future<void> _loadShader() async {
    try {
      final program = await (_programFuture ??= ui.FragmentProgram.fromAsset(
        'shaders/nexa_liquid_glass.frag',
      ));
      final shader = program.fragmentShader();
      if (!mounted) {
        shader.dispose();
        return;
      }
      debugPrint('NexaDrive glass: Impeller optical refraction shader loaded.');
      setState(() => _shader = shader);
    } catch (error, stackTrace) {
      // A shader compilation/asset failure must never make the whole app
      // unusable. The normal GPU blur remains a fully functional fallback.
      _programFuture = null;
      debugPrint('NexaDrive glass shader failed to load: $error');
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'NexaDrive Liquid Glass',
          context: ErrorDescription('while loading the optical glass shader'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  ui.ImageFilter _backdropFilter(BuildContext context) {
    final sigma = widget.blurSigma.clamp(0.0, 24.0).toDouble();
    final blur = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
    final shader = _shader;

    if (shader == null || !ui.ImageFilter.isShaderFilterSupported) {
      return blur;
    }

    // ImageFilter.shader reserves floats 0 and 1 for the input texture size.
    // The vec4 corner radii therefore begin at float slot 2. Flutter supplies
    // the size and sampler automatically; Dart must not overwrite either.
    try {
      final radii = widget.borderRadius.resolve(Directionality.of(context));
      final pixelRatio = MediaQuery.devicePixelRatioOf(context);
      shader
        ..setFloat(2, radii.topLeft.x * pixelRatio)
        ..setFloat(3, radii.topRight.x * pixelRatio)
        ..setFloat(4, radii.bottomRight.x * pixelRatio)
        ..setFloat(5, radii.bottomLeft.x * pixelRatio);

      // ImageFilter.compose applies inner first, then outer: blur the scene,
      // then refract that blurred scene through the glass lens.
      return ui.ImageFilter.compose(
        outer: ui.ImageFilter.shader(shader),
        inner: blur,
      );
    } catch (error, stackTrace) {
      // Renderer/device-specific failures degrade safely but remain visible
      // in logs.
      if (!_shaderFilterErrorReported) {
        debugPrint(
          'NexaDrive glass filter failed; using blur fallback: $error',
        );
        _shaderFilterErrorReported = true;
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'NexaDrive Liquid Glass',
            context: ErrorDescription('while creating the glass image filter'),
          ),
        );
      }
      return blur;
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final highContrast = MediaQuery.maybeOf(context)?.highContrast ?? false;
    final opaque = widget.forceOpaque || highContrast || !widget.enabled;
    final dark = brightness == Brightness.dark;
    final tint = AppColors.glassSurfaceFor(brightness);
    final tintAlpha = (widget.tintOpacity ?? (dark ? 0.075 : 0.065))
        .clamp(0.0, 0.24)
        .toDouble();
    final edge = dark
        ? Colors.white.withValues(alpha: 0.34)
        : Colors.white.withValues(alpha: 0.72);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius,
        boxShadow: widget.showShadow
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
        borderRadius: widget.borderRadius,
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            if (!opaque)
              Positioned.fill(
                child: BackdropFilter(
                  filter: _backdropFilter(context),
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
            if (!opaque && widget.showHighlight)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: dark
                            ? [
                                Colors.white.withValues(alpha: 0.075),
                                Colors.white.withValues(alpha: 0.012),
                                Colors.black.withValues(alpha: 0.018),
                              ]
                            : [
                                Colors.white.withValues(alpha: 0.22),
                                Colors.white.withValues(alpha: 0.035),
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
              padding: widget.padding,
              child: Material(
                type: MaterialType.transparency,
                child: widget.child,
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: widget.borderRadius,
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
