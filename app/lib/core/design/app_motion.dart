import 'package:flutter/material.dart';

/// NexaDrive One UI motion tokens.
///
/// One UI motion is restrained, confident, and physical. Springs should be
/// critically damped by default; bounce only for momentum-driven gestures.
/// Every duration and curve in NexaDrive must come from this file.
abstract final class AppMotion {
  // ------------------------------------------------------------ durations
  /// Micro-interactions: press highlight, toggle, checkbox.
  static const Duration micro = Duration(milliseconds: 120);

  /// Small state changes: row highlight, icon swap, counters.
  static const Duration fast = Duration(milliseconds: 180);

  /// Default UI motion: sheet slide, page transitions, expand/collapse.
  static const Duration normal = Duration(milliseconds: 300);

  /// Deliberate motion: page transitions on navigation.
  static const Duration slow = Duration(milliseconds: 380);

  // --------------------------------------------------------------- curves
  /// One UI easing: fast start, gentle settle — the "responsive" feel.
  static const Curve standard = Cubic(0.25, 0.1, 0.3, 1);

  /// Slightly snappier entrance (sheets, panels arriving).
  static const Curve enter = Cubic(0.15, 0.85, 0.25, 1);

  /// Soft exit (dismiss, close) — the reverse of [enter] path.
  static const Curve exit = Cubic(0.45, 0.05, 0.85, 0.2);

  /// Ease for opacity-only fades.
  static const Curve fade = Curves.easeOut;

  // ------------------------------------------------------------- springs
  /// Page/sheet settle — critically damped, no bounce.
  static const double springResponse = 0.35;
  static const double springDamping = 1.0;

  /// The resolved spring used wherever tactile physics is warranted
  /// (critical damping 1.0; lower damping only for momentum gestures).
  /// stiffness = mass/response² and damping = 2·ratio/response, so for
  /// response 0.35 / damping 1.0 that is stiffness 8.16, damping 5.71.
  static SpringDescription get spring => const SpringDescription(
        mass: 1.0,
        stiffness: 8.1633,
        damping: 5.7143,
      );

  /// A slightly faster spring for micro-touch feedback (press states).
  static SpringDescription get microSpring => const SpringDescription(
        mass: 1.0,
        stiffness: 20.6612,
        damping: 9.0909,
      );

  // ------------------------------------------------------------- helpers
  /// A standard animated swapper for content changes.
  static AnimatedSwitcher defaultSwitcher({Key? key, Widget? child}) =>
      AnimatedSwitcher(
        key: key,
        duration: fast,
        switchInCurve: enter,
        switchOutCurve: exit,
        reverseDuration: fast,
        child: child,
      );

  /// Whether reduced motion is active for the current context.
  static bool reducedMotion(BuildContext context) {
    final data = MediaQuery.maybeOf(context);
    return data != null && data.disableAnimations;
  }

  /// Resolves a normal duration to a near-instant one when reduced motion is
  /// requested.
  static Duration resolve(BuildContext context, Duration value) =>
      reducedMotion(context) ? Duration.zero : value;

  /// Resolves the latest frame of a drive animation on reduced motion.
  static Curve curveFor(BuildContext context, Curve curve) =>
      reducedMotion(context) ? Curves.linear : curve;
}