import 'package:flutter/material.dart';

import '../../core/design/app_motion.dart';
import 'nexa_motion.dart';

/// Adds the shared spring-driven tactile feedback to an existing control.
///
/// This is the compatibility name for [NexaElasticPress]. It never handles the
/// gesture itself: a passive [Listener] lets taps, long presses, ink responses
/// and accessibility actions flow to the child unchanged. Layout, hit area,
/// colours and typography are untouched; only the paint transform (and, when a
/// tint is supplied, a translucent overlay) responds to a press.
///
/// Full-width rows should pass `false` for [scale] and use [tintColor] instead:
/// shrinking a row exposes its background and reads as a layout glitch.
/// Reduced motion snaps between states instead of springing.
class NexaPressable extends StatelessWidget {
  final Widget child;

  /// Whether feedback is allowed. Disabled controls stay perfectly still.
  final bool enabled;

  /// Whether the control scales while pressed.
  final bool scale;

  /// Scale reached while held. Prefer [AppMotion.pressScale] for controls and
  /// [AppMotion.pressScaleMedia] for artwork.
  final double pressedScale;

  /// Optional press highlight, painted at its own alpha while pressed.
  final Color? tintColor;

  /// Clip radius for [tintColor].
  final BorderRadius? borderRadius;

  const NexaPressable({
    super.key,
    required this.child,
    this.enabled = true,
    this.scale = true,
    this.pressedScale = AppMotion.pressScale,
    this.tintColor,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return NexaElasticPress(
      enabled: enabled,
      scale: scale,
      pressedScale: pressedScale,
      tintColor: tintColor,
      borderRadius: borderRadius,
      child: child,
    );
  }
}
