import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';

/// A bounded optical-glass surface over the live scene.
///
/// The shader receives two different coordinate spaces:
/// - [u_size] is the scene texture size supplied by Impeller.
/// - card origin/size are measured from this render object's actual paint
///   transform. Treating those sizes as interchangeable makes a glass pill
///   refract around the wrong centre, which looks like ordinary blur.
///
/// Refraction is an Impeller ImageFilter shader, not a blur or a painted
/// gradient. On Skia / unsupported devices this widget reports a clear
/// compatibility fallback (blur + tint) instead of pretending it refracts.
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

  /// Width of the curved optical shoulder, in logical pixels.
  final double refractionHeight;

  /// Negative values pull the scene toward the inner edge of the lens.
  final double refractionAmount;

  /// Gently bends the lens normal toward the surface centre.
  final double depthEffect;

  /// RGB channel separation near curved corners. Set to zero to disable.
  final double chromaticDispersion;

  const NexaLiquidGlass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(
      Radius.circular(AppDimens.radiusMedium),
    ),
    this.padding = const EdgeInsets.all(AppDimens.space12),
    this.blurSigma = 2.0,
    this.enabled = true,
    this.forceOpaque = false,
    this.showHighlight = true,
    this.showShadow = true,
    this.tintOpacity,
    this.refractionHeight = 20,
    this.refractionAmount = -34,
    this.depthEffect = 0.72,
    this.chromaticDispersion = 1.0,
  }) : assert(refractionHeight >= 0),
       assert(depthEffect >= 0 && depthEffect <= 1.5),
       assert(chromaticDispersion >= 0 && chromaticDispersion <= 3);
  
  @override
  State<NexaLiquidGlass> createState() => _NexaLiquidGlassState();
}

class _NexaLiquidGlassState extends State<NexaLiquidGlass> {
  static Future<ui.FragmentProgram>? _programFuture;

  ui.FragmentProgram? _program;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _loadShader();
  }

  Future<void> _loadShader() async {
    if (!ui.ImageFilter.isShaderFilterSupported) {
      debugPrint(
        'NexaDrive glass: ImageFilter.shader is unavailable on this renderer; '
        'using the explicit frosted fallback.',
      );
      return;
    }

    try {
      final program = await (_programFuture ??= ui.FragmentProgram.fromAsset(
        'shaders/nexa_liquid_glass.frag',
      ));
      if (!mounted) return;
      debugPrint(
        'NexaDrive glass: scene-aligned Impeller refraction shader loaded.',
      );
      setState(() => _program = program);
    } catch (error, stackTrace) {
      _programFuture = null;
      _loadFailed = true;
      debugPrint('NexaDrive glass shader failed to load: $error');
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'NexaDrive Liquid Glass',
          context: ErrorDescription('while loading the optical glass shader'),
        ),
      );
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final highContrast = MediaQuery.maybeOf(context)?.highContrast ?? false;
    final opaque = widget.forceOpaque || highContrast || !widget.enabled;
    final dark = brightness == Brightness.dark;
    final tint = AppColors.glassSurfaceFor(brightness);
    final tintAlpha = (widget.tintOpacity ?? (dark ? 0.075 : 0.06))
        .clamp(0.0, 0.24)
        .toDouble();
    final edge = dark
        ? Colors.white.withValues(alpha: 0.46)
        : Colors.white.withValues(alpha: 0.86);

    final radius = widget.borderRadius.resolve(Directionality.of(context));
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final params = _NexaGlassParams(
      topLeftRadius: radius.topLeft.x * dpr,
      topRightRadius: radius.topRight.x * dpr,
      bottomRightRadius: radius.bottomRight.x * dpr,
      bottomLeftRadius: radius.bottomLeft.x * dpr,
      refractionHeight: widget.refractionHeight * dpr,
      refractionAmount: widget.refractionAmount * dpr,
      depthEffect: widget.depthEffect,
      chromaticDispersion: widget.chromaticDispersion,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius,
        boxShadow: widget.showShadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.30 : 0.10),
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
                child: _program != null && !_loadFailed
                    ? _NexaGlassBackdrop(
                        program: _program!,
                        params: params,
                        blurSigma: widget.blurSigma,
                        child: const SizedBox.expand(),
                      )
                    : BackdropFilter(
                        filter: ui.ImageFilter.blur(
                          sigmaX: widget.blurSigma.clamp(0.0, 24.0),
                          sigmaY: widget.blurSigma.clamp(0.0, 24.0),
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
            if (!opaque && widget.showHighlight)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: dark
                            ? [
                                Colors.white.withValues(alpha: 0.105),
                                Colors.white.withValues(alpha: 0.018),
                                Colors.black.withValues(alpha: 0.035),
                              ]
                            : [
                                Colors.white.withValues(alpha: 0.30),
                                Colors.white.withValues(alpha: 0.045),
                                const Color(0xFF7770A8)
                                    .withValues(alpha: 0.025),
                              ],
                        stops: const [0, 0.48, 1],
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
                child: CustomPaint(
                  painter: _NexaGlassEdgePainter(
                    borderRadius: widget.borderRadius,
                    dark: dark,
                    enabled: !opaque && widget.showHighlight,
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

/// Only the values that affect the optical lens. All lengths are physical px
/// by the time they are bound to the shader.
@immutable
class _NexaGlassParams {
  final double topLeftRadius;
  final double topRightRadius;
  final double bottomRightRadius;
  final double bottomLeftRadius;
  final double refractionHeight;
  final double refractionAmount;
  final double depthEffect;
  final double chromaticDispersion;

  const _NexaGlassParams({
    required this.topLeftRadius,
    required this.topRightRadius,
    required this.bottomRightRadius,
    required this.bottomLeftRadius,
    required this.refractionHeight,
    required this.refractionAmount,
    required this.depthEffect,
    required this.chromaticDispersion,
  });

  void bind(
    ui.FragmentShader shader, {
    required Offset origin,
    required Size size,
  }) {
    final maxRadius = size.shortestSide * 0.5;
    shader
      ..setFloat(2, origin.dx)
      ..setFloat(3, origin.dy)
      ..setFloat(4, size.width)
      ..setFloat(5, size.height)
      ..setFloat(6, topLeftRadius.clamp(0.0, maxRadius))
      ..setFloat(7, topRightRadius.clamp(0.0, maxRadius))
      ..setFloat(8, bottomRightRadius.clamp(0.0, maxRadius))
      ..setFloat(9, bottomLeftRadius.clamp(0.0, maxRadius))
      ..setFloat(10, refractionHeight)
      ..setFloat(11, refractionAmount)
      ..setFloat(12, depthEffect)
      ..setFloat(13, chromaticDispersion);
  }
}

/// Paints an Impeller backdrop filter using the *actual* scene-space bounds of
/// the glass render box. This is the important distinction from a widget-built
/// ImageFilter: its input texture may be scene-sized, while the dock/panel is
/// only a small rectangle within that scene.
class _NexaGlassBackdrop extends SingleChildRenderObjectWidget {
  final ui.FragmentProgram program;
  final _NexaGlassParams params;
  final double blurSigma;

  const _NexaGlassBackdrop({
    required this.program,
    required this.params,
    required this.blurSigma,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _NexaGlassBackdropRenderObject(
      program.fragmentShader(),
      params,
      MediaQuery.devicePixelRatioOf(context),
      blurSigma,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _NexaGlassBackdropRenderObject renderObject,
  ) {
    renderObject.update(
      params,
      MediaQuery.devicePixelRatioOf(context),
      blurSigma,
    );
  }
}

class _NexaGlassBackdropRenderObject extends RenderProxyBox {
  _NexaGlassBackdropRenderObject(
    this._shader,
    this._params,
    this._devicePixelRatio,
    this._blurSigma,
  );

  final ui.FragmentShader _shader;
  _NexaGlassParams _params;
  double _devicePixelRatio;
  double _blurSigma;
  bool _shaderFilterFailed = false;

  void update(
    _NexaGlassParams params,
    double devicePixelRatio,
    double blurSigma,
  ) {
    if (_params == params &&
        _devicePixelRatio == devicePixelRatio &&
        _blurSigma == blurSigma) {
      return;
    }
    _params = params;
    _devicePixelRatio = devicePixelRatio;
    _blurSigma = blurSigma;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null || size.isEmpty) return;

    // getTransformTo(null) is queried at paint time, after the dock/panel has
    // its final position. Reading this during build/layout would often bind a
    // zero origin and make the SDF lens miss the visible glass surface.
    final sceneBounds = MatrixUtils.transformRect(
      getTransformTo(null),
      Offset.zero & size,
    );
    _params.bind(
      _shader,
      origin: Offset(
        sceneBounds.left * _devicePixelRatio,
        sceneBounds.top * _devicePixelRatio,
      ),
      size: Size(
        sceneBounds.width * _devicePixelRatio,
        sceneBounds.height * _devicePixelRatio,
      ),
    );

    final blur = ui.ImageFilter.blur(
      sigmaX: _blurSigma.clamp(0.0, 24.0),
      sigmaY: _blurSigma.clamp(0.0, 24.0),
    );

    ui.ImageFilter filter = blur;
    if (!_shaderFilterFailed && ui.ImageFilter.isShaderFilterSupported) {
      try {
        // ImageFilter.compose applies inner first: blur the scene, then bend
        // its pixels through the SDF lens.
        filter = ui.ImageFilter.compose(
          outer: ui.ImageFilter.shader(_shader),
          inner: blur,
        );
      } catch (error, stackTrace) {
        _shaderFilterFailed = true;
        debugPrint(
          'NexaDrive glass filter failed; using blur fallback: $error',
        );
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'NexaDrive Liquid Glass',
            context: ErrorDescription(
              'while creating the scene-aligned refraction filter',
            ),
          ),
        );
      }
    }

    final backdropLayer =
        (layer ??= BackdropFilterLayer()) as BackdropFilterLayer;
    backdropLayer
      ..filter = filter
      ..blendMode = BlendMode.srcOver;
    context.pushLayer(backdropLayer, super.paint, offset);
  }

  @override
  void dispose() {
    _shader.dispose();
    super.dispose();
  }
}

/// Directional edge lighting: a bright upper bevel and a quieter lower rim.
/// The backdrop itself is refracted by the fragment shader above.
class _NexaGlassEdgePainter extends CustomPainter {
  final BorderRadiusGeometry borderRadius;
  final bool dark;
  final bool enabled;

  const _NexaGlassEdgePainter({
    required this.borderRadius,
    required this.dark,
    required this.enabled,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!enabled || size.isEmpty) return;
    final rect = Offset.zero & size;
    final rrect = borderRadius.resolve(TextDirection.ltr).toRRect(rect);
    final upper = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: dark
            ? [
                Colors.white.withValues(alpha: 0.62),
                Colors.white.withValues(alpha: 0.10),
                Colors.black.withValues(alpha: 0.25),
              ]
            : [
                Colors.white.withValues(alpha: 0.94),
                Colors.white.withValues(alpha: 0.26),
                Colors.black.withValues(alpha: 0.10),
              ],
        stops: const [0, 0.45, 1],
      ).createShader(rect);
    canvas.drawRRect(rrect.deflate(0.55), upper);

    final inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.65
      ..color = (dark ? Colors.white : Colors.white).withValues(
        alpha: dark ? 0.18 : 0.34,
      );
    canvas.drawRRect(rrect.deflate(2.0), inner);
  }

  @override
  bool shouldRepaint(covariant _NexaGlassEdgePainter oldDelegate) =>
      borderRadius != oldDelegate.borderRadius ||
      dark != oldDelegate.dark ||
      enabled != oldDelegate.enabled;
}
