import 'package:flutter/material.dart';

/// NexaDrive motion tokens.
///
/// THE REFERENCE: Apple's animation guidance. Motion is responsive and
/// physical: springs are critically damped by default, bounces are reserved for
/// momentum-driven gestures, and nothing delays a user action. Every duration,
/// curve and spring in NexaDrive must come from this file.
abstract final class AppMotion {
  // ------------------------------------------------------------ durations
  /// Micro-interactions: press highlight, toggle, checkbox.
  static const Duration micro = Duration(milliseconds: 120);

  /// Small state changes: row highlight, icon swap, counters.
  static const Duration fast = Duration(milliseconds: 180);

  /// Default UI motion: sheet slide, expand/collapse.
  static const Duration normal = Duration(milliseconds: 300);

  /// Standard navigation push/pop.
  static const Duration navigation = Duration(milliseconds: 350);

  /// Deliberate motion: full-screen transitions.
  static const Duration slow = Duration(milliseconds: 420);

  // --------------------------------------------------------------- curves
  /// iOS-style standard easing: fast start, gentle settle.
  static const Curve standard = Cubic(0.25, 0.1, 0.25, 1.0);
  static const Curve standardCurve = Cubic(0.25, 0.1, 0.25, 1.0);

  /// Slightly snappier entrance (sheets, panels arriving).
  static const Curve enter = Cubic(0.15, 0.85, 0.3, 1.0);
  static const Curve enterCurve = Cubic(0.15, 0.85, 0.3, 1.0);

  /// Soft exit (dismiss, close).
  static const Curve exit = Cubic(0.45, 0.05, 0.85, 0.2);
  static const Curve exitCurve = Cubic(0.45, 0.05, 0.85, 0.2);

  /// Ease for opacity-only fades.
  static const Curve fade = Curves.easeOut;
  static const Curve fadeCurve = Curves.easeOut;

  /// Spring-like curve for interactive gestures (pull, drag settle).
  static const Curve springCurve = Cubic(0.17, 0.89, 0.32, 1.0);

  // ------------------------------------------------------------- springs
  /// Page/sheet settle — critically damped, no bounce.
  static const double springResponse = 0.35;
  static const double springDamping = 1.0;

  /// The resolved spring used wherever tactile physics is warranted
  /// (critical damping 1.0; lower damping only for momentum gestures).
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

  /// Named spring handles (aliases over [spring]/[microSpring]).
  static SpringDescription get standardSpring => spring;
  static SpringDescription get dragSpring => const SpringDescription(
        mass: 1.0,
        stiffness: 100,
        damping: 15,
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

  /// A cross-fade for boolean state changes.
  static AnimatedCrossFade crossFade({
    required bool first,
    required Widget firstChild,
    required Widget secondChild,
    Duration? duration,
    Curve? firstCurve,
    Curve? secondCurve,
  }) =>
      AnimatedCrossFade(
        firstChild: firstChild,
        secondChild: secondChild,
        crossFadeState:
            first ? CrossFadeState.showFirst : CrossFadeState.showSecond,
        duration: duration ?? normal,
        firstCurve: firstCurve ?? enter,
        secondCurve: secondCurve ?? exit,
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

  /// Resolves a curve to linear when reduced motion is requested.
  static Curve curveFor(BuildContext context, Curve curve) =>
      reducedMotion(context) ? Curves.linear : curve;

  /// Alias for [curveFor] used by layout code.
  static Curve resolveCurve(BuildContext context, Curve curve) =>
      curveFor(context, curve);
}
