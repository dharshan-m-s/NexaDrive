import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// NexaDrive motion tokens.
///
/// Visual composition follows One UI's restraint; interaction follows the
/// continuity and feedback quality expected from native iOS. Motion is
/// responsive and physical: springs are critically damped by default, bounces
/// are reserved for momentum-driven gestures, and nothing delays a user action.
/// Every duration, curve and spring in NexaDrive must come from this file.
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

  /// Low-amplitude skeleton breathing; disabled entirely for reduced motion.
  static const Duration ambient = Duration(milliseconds: 1400);

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

  /// Restraint spring for the floating dock's travelling selection.
  static const SpringDescription glassSpring = SpringDescription(
    mass: 1.0,
    stiffness: 320.0,
    damping: 25.75,
  );

  // -------------------------------------------------------- press feedback
  /// Scale applied while a control is held. Small enough to read as pressure
  /// rather than a layout change.
  static const double pressScale = 0.985;

  /// Slightly deeper press for artwork-like tiles (grid cards, media).
  static const double pressScaleMedia = 0.975;

  /// Press-down: stiff and critically damped (ζ = 1.0), so the control reaches
  /// its pressed scale in roughly 150 ms without wobbling on the way in.
  static const SpringDescription pressSpring = SpringDescription(
    mass: 1.0,
    stiffness: 1200.0,
    damping: 69.282, // ζ = 1.0
  );

  /// Press-release: lightly underdamped (ζ = 0.78) so the control settles back
  /// with a whisper of overshoot instead of snapping flat.
  static const SpringDescription pressReleaseSpring = SpringDescription(
    mass: 1.0,
    stiffness: 900.0,
    damping: 46.8, // ζ = 0.78
  );

  // ---------------------------------------------------------- scroll settle
  /// Settle spring for bouncing overscroll: the same calm return iOS uses when
  /// a rubber-banded scroll comes to rest. Matches Flutter's own bouncing
  /// spring so native platform feel is preserved.
  static const SpringDescription scrollSpring = SpringDescription(
    mass: 0.5,
    stiffness: 100.0,
    damping: 15.5563, // ζ = 1.1
  );

  // ------------------------------------------------------------- helpers
  /// Drives [controller] toward [target] with [spring].
  ///
  /// Reduced motion skips the simulation and jumps to the target, so press
  /// feedback never becomes waiting.
  static void springTo(
    AnimationController controller, {
    required double target,
    required SpringDescription spring,
    required bool reducedMotion,
  }) {
    if (reducedMotion) {
      controller
        ..stop()
        ..value = target;
      return;
    }
    controller.animateWith(
      SpringSimulation(spring, controller.value, target, controller.velocity),
    );
  }

  /// Sheet route motion: the body rises on the enter curve and dismisses a
  /// touch faster than it arrived, so closing never feels sticky.
  static const AnimationStyle sheetAnimationStyle = AnimationStyle(
    duration: normal,
    reverseDuration: fast,
    curve: enter,
    reverseCurve: exit,
  );

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
