import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// NexaDrive motion — Material 3 motion tokens.
///
/// Standard, entering and exiting curves come from Material's emphasized
/// motion spec. Springs remain only where the user can grab and redirect a
/// surface (the floating navigation pill); everything else uses short,
/// interruptible durations. All durations and curves live here.
abstract final class AppMotion {
  // ------------------------------------------------------------ durations
  static const Duration micro = Duration(milliseconds: 100);
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 300);
  static const Duration navigation = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 500);
  static const Duration ambient = Duration(milliseconds: 1400);

  // --------------------------------------------------------------- curves
  /// M3 standard / emphasized easing.
  static const Curve standard = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Curve standardCurve = standard;

  /// M3 entering: decelerate into place.
  static const Curve enter = Cubic(0.0, 0.0, 0.0, 1.0);
  static const Curve enterCurve = enter;

  /// M3 exiting: accelerate away.
  static const Curve exit = Cubic(0.4, 0.0, 1.0, 1.0);
  static const Curve exitCurve = exit;

  static const Curve fade = Curves.easeOut;
  static const Curve fadeCurve = fade;

  /// Reserved for gesture-driven spring-like interpolation.
  static const Curve springCurve = Cubic(0.2, 0.0, 0.0, 1.0);

  // ------------------------------------------------------------- springs
  static const double springResponse = 0.3;
  static const double springDamping = 1.0;

  static SpringDescription get spring => const SpringDescription(
        mass: 1.0,
        stiffness: 210.0,
        damping: 27.0,
      );

  static SpringDescription get microSpring => const SpringDescription(
        mass: 1.0,
        stiffness: 420.0,
        damping: 40.0,
      );

  static SpringDescription get standardSpring => spring;

  static const SpringDescription dragSpring = SpringDescription(
    mass: 1.0,
    stiffness: 180.0,
    damping: 24.0,
  );

  /// Spring for the floating pill's travelling selection. Near-critically
  /// damped so the signature motion stays responsive without a rubbery
  /// overshoot on every tap.
  static const SpringDescription pillSpring = SpringDescription(
    mass: 1.0,
    stiffness: 320.0,
    damping: 34.0,
  );

  /// Legacy alias for [pillSpring].
  static const SpringDescription glassSpring = pillSpring;

  // -------------------------------------------------------- press feedback
  static const double pressScale = 0.98;
  static const double pressScaleMedia = 0.975;

  static const SpringDescription pressSpring = SpringDescription(
    mass: 1.0,
    stiffness: 1200.0,
    damping: 69.282,
  );

  static const SpringDescription pressReleaseSpring = SpringDescription(
    mass: 1.0,
    stiffness: 900.0,
    damping: 46.8,
  );

  // ---------------------------------------------------------- scroll settle
  static const SpringDescription scrollSpring = SpringDescription(
    mass: 0.5,
    stiffness: 180.0,
    damping: 24.0,
  );

  // ------------------------------------------------------------- helpers
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

  static const AnimationStyle sheetAnimationStyle = AnimationStyle(
    duration: normal,
    reverseDuration: fast,
    curve: enter,
    reverseCurve: exit,
  );

  static AnimatedSwitcher defaultSwitcher({Key? key, Widget? child}) =>
      AnimatedSwitcher(
        key: key,
        duration: fast,
        switchInCurve: enter,
        switchOutCurve: exit,
        reverseDuration: fast,
        child: child,
      );

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

  static bool reducedMotion(BuildContext context) {
    final data = MediaQuery.maybeOf(context);
    return data != null && data.disableAnimations;
  }

  static Duration resolve(BuildContext context, Duration value) =>
      reducedMotion(context) ? Duration.zero : value;

  static Curve curveFor(BuildContext context, Curve curve) =>
      reducedMotion(context) ? Curves.linear : curve;

  static Curve resolveCurve(BuildContext context, Curve curve) =>
      curveFor(context, curve);
}
