import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// NexaDrive motion — the single Material 3 motion system.
///
/// Durations and curves come from Material's standard/emphasised easing.
/// Springs are reserved for surfaces the user can grab or redirect (sheets,
/// the floating navigation pill, press feedback); everything else uses short,
/// interruptible transitions. All timings live here.
///
/// Two independent reduce signals are honoured:
///
/// * [MediaQueryData.disableAnimations] (platform accessibility), which always
///   means "no motion at all"; and
/// * the app-level preference in [appReduceAnimations], which replaces elaborate
///   transitions with immediate changes or short, non-positional fades.
abstract final class AppMotion {
  // ------------------------------------------------------------ durations
  static const Duration micro = Duration(milliseconds: 100);
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 300);
  static const Duration navigation = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 500);
  static const Duration ambient = Duration(milliseconds: 1400);

  /// Short fade used when the app-level reduce preference is on but an
  /// accessibility-level "disable animations" is not.
  static const Duration stateFade = micro;

  /// Total budget for one bounded entrance stagger (including its last item).
  static const Duration staggerDuration = Duration(milliseconds: 260);
  static const Duration staggerStep = Duration(milliseconds: 45);
  static const Duration staggerItem = Duration(milliseconds: 180);
  static const int maxStaggerItems = 4;
  static const double staggerOffset = 8.0;

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

  /// Fluid reveal: a restrained Material ease-out with a ~2% overshoot.
  ///
  /// Used for short, interruptible content reveals (scale/slide). Opacity must
  /// be clamped when driven by this curve: [FadeTransition] only accepts 0..1.
  static const Curve fluid = Cubic(0.0, 0.0, 0.2, 1.18);
  static const Curve fluidCurve = fluid;

  /// Reserved for gesture-driven spring-like interpolation.
  static const Curve springCurve = Cubic(0.2, 0.0, 0.0, 1.0);

  /// Controlled, near-critically damped settle used by sheets and revealed
  /// surfaces. It reads as a spring without a rubbery overshoot.
  static const Curve sheetSettleCurve = standard;

  /// Floating page chrome glides to its rest edge after a scroll ends. It is
  /// short enough never to feel like the page is catching up with the finger,
  /// yet long enough for a partly exposed header to read as one continuous
  /// surface. Mirrored M3 easing makes leaving and returning feel like the same
  /// physical path.
  static const Duration headerSettle = Duration(milliseconds: 280);
  static const Curve headerRevealCurve = enter;
  static const Curve headerHideCurve = exit;

  /// Connected route transition: both pages share one fade, and the incoming
  /// page eases a few pixels forward into its final scale.
  static const Curve routeFadeCurve = enter;
  static const Curve routeScaleCurve = standard;
  static const double routeScaleBegin = 0.99;
  static const double routeFadeOutEnd = 0.0;

  /// Press compression and release are intentionally asymmetric: the press is
  /// immediate, the release settles. Neither curve bounces.
  static const Curve pressDownCurve = Curves.easeOut;
  static const Curve pressReleaseCurve = Cubic(0.16, 1.0, 0.3, 1.0);

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

  /// General-purpose controlled preset for a surface settling into place.
  static const SpringDescription controlledSpring = SpringDescription(
    mass: 1.0,
    stiffness: 300.0,
    damping: 34.0,
  );

  /// Slower, quieter preset for larger moving geometry.
  static const SpringDescription gentleSpring = SpringDescription(
    mass: 1.0,
    stiffness: 260.0,
    damping: 32.0,
  );

  static const SpringDescription dragSpring = SpringDescription(
    mass: 1.0,
    stiffness: 180.0,
    damping: 24.0,
  );

  /// Spring used when a dragged sheet is released and snaps to its rest state.
  static const SpringDescription sheetSettleSpring = standardSpringAlias;
  static const SpringDescription standardSpringAlias = SpringDescription(
    mass: 1.0,
    stiffness: 210.0,
    damping: 27.0,
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

  /// Named elastic presets used by [NexaElasticPress] and every pressable
  /// Nexa control. Kept separate from layout springs so a tap never feels like
  /// a dragged surface.
  static const SpringDescription elasticPress = pressSpring;
  static const SpringDescription elasticRelease = pressReleaseSpring;

  // ---------------------------------------------------------- scroll settle
  static const SpringDescription scrollSpring = SpringDescription(
    mass: 0.5,
    stiffness: 180.0,
    damping: 24.0,
  );

  /// Edge resistance for long lists. The closer the content is to its limit,
  /// the harder it pulls back, so reaching the end reads as responsive instead
  /// of frozen. The floating-header coordinator yields while out of range.
  static const ScrollPhysics elasticScrollPhysics = BouncingScrollPhysics();

  /// Native floating-header snap: animates the chrome alone, leaving the list
  /// offset untouched. This is what keeps a deep Files/Photos scroll in place
  /// when the top bar returns.
  static FloatingHeaderSnapConfiguration headerSnapFor(BuildContext context) =>
      FloatingHeaderSnapConfiguration(
        curve: reducedMotion(context) ? Curves.linear : headerRevealCurve,
        duration: resolve(context, headerSettle),
      );

  // -------------------------------------------------------- gesture limits
  /// Distance after which a press is treated as a scroll/drag and released.
  static const double pressTouchSlop = kTouchSlop;

  /// A fast drag cancels press feedback even before it travels [pressTouchSlop].
  static const double pressVelocityThreshold = 900.0;

  /// Velocity (logical pixels/second) that decides a drag snap by direction.
  static const double dragVelocityThreshold = 800.0;

  /// A short drag still completes when it passes this fraction of its range.
  static const double dragDismissFraction = 0.35;

  /// Bounded settle duration for a drag that did not cross a velocity threshold.
  static const Duration dragSnapDuration = fast;

  // ------------------------------------------------------------- preference
  /// SharedPreferences key for the app-level reduce-animations switch.
  static const String reduceAnimationsPreferenceKey = 'reduce_animations';

  /// App-level preference, loaded once at startup and notified live so an
  /// in-settings change takes effect without restarting the app.
  static final ValueNotifier<bool> appReduceAnimations = ValueNotifier<bool>(
    false,
  );

  static bool get appReducedMotion => appReduceAnimations.value;

  /// Loads the persisted preference. Pass the app's existing [SharedPreferences]
  /// instance so startup reads it once.
  static Future<void> loadReduceAnimationsPreference([
    SharedPreferences? prefs,
  ]) async {
    final store = prefs ?? await SharedPreferences.getInstance();
    appReduceAnimations.value =
        store.getBool(reduceAnimationsPreferenceKey) ?? false;
  }

  /// Persists and applies the app-level preference. The in-memory value changes
  /// first so the UI responds immediately; the write uses the existing
  /// SharedPreferences pattern.
  static Future<void> setReduceAnimations(
    bool value, {
    SharedPreferences? prefs,
  }) async {
    if (appReduceAnimations.value != value) {
      appReduceAnimations.value = value;
    }
    final store = prefs ?? await SharedPreferences.getInstance();
    await store.setBool(reduceAnimationsPreferenceKey, value);
  }

  /// Test-only reset so a notifier value cannot leak between widget tests.
  static void resetMotionPreferenceForTesting() {
    appReduceAnimations.value = false;
  }

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

  /// True only when the platform accessibility setting disables animations.
  /// This signal is never softened: it always means an immediate change.
  static bool systemReducedMotion(BuildContext context) {
    final data = MediaQuery.maybeOf(context);
    return data != null && data.disableAnimations;
  }

  /// True when either the platform or the app asks for reduced motion.
  static bool reducedMotion(BuildContext context) =>
      systemReducedMotion(context) || appReducedMotion;

  static Duration resolve(BuildContext context, Duration value) =>
      reducedMotion(context) ? Duration.zero : value;

  /// Resolves a state change: platform reduce is instant, app-level reduce is a
  /// short fade, and the default uses [full]. Essential information is never
  /// gated behind a long transition.
  static Duration resolveStateChange(
    BuildContext context,
    Duration full, {
    Duration fade = stateFade,
  }) {
    if (systemReducedMotion(context)) return Duration.zero;
    if (appReducedMotion) return fade;
    return full;
  }

  static Curve curveFor(BuildContext context, Curve curve) =>
      reducedMotion(context) ? Curves.linear : curve;

  static Curve resolveCurve(BuildContext context, Curve curve) =>
      curveFor(context, curve);

  /// Scale presets collapse to 1.0 whenever motion is reduced.
  static double resolveScale(BuildContext context, double scale) =>
      reducedMotion(context) ? 1.0 : scale;

  static bool exceedsVelocity(
    Offset delta,
    Duration elapsed, {
    double threshold = pressVelocityThreshold,
  }) {
    final seconds = elapsed.inMicroseconds / 1000000.0;
    return seconds > 0 && delta.distance / seconds >= threshold;
  }

  /// Chooses the nearer snap target, unless a flick decides the direction.
  static double resolveSnapTarget({
    required double current,
    required double velocity,
    required double min,
    required double max,
    double velocityThreshold = dragVelocityThreshold,
  }) {
    assert(min <= max);
    if (velocity.abs() >= velocityThreshold) {
      return velocity > 0 ? max : min;
    }
    return current >= (min + max) / 2 ? max : min;
  }

  /// Whether a drag should dismiss instead of snapping back.
  static bool shouldDismissDrag({
    required double extent,
    required double velocity,
    required double totalExtent,
    double velocityThreshold = dragVelocityThreshold,
  }) {
    if (totalExtent <= 0) return false;
    if (velocity.abs() >= velocityThreshold) return velocity > 0;
    return extent / totalExtent >= dragDismissFraction;
  }

  /// Keeps snap durations bounded between [fast] and [normal].
  static Duration settleDurationFor(double distance) {
    final milliseconds = (fast.inMilliseconds + distance.abs() / 8).round();
    return Duration(
      milliseconds: milliseconds
          .clamp(fast.inMilliseconds, normal.inMilliseconds)
          .toInt(),
    );
  }

  static const AnimationStyle sheetAnimationStyle = AnimationStyle(
    duration: normal,
    reverseDuration: fast,
    curve: sheetSettleCurve,
    reverseCurve: exit,
  );

  static const AnimationStyle routeAnimationStyle = AnimationStyle(
    duration: navigation,
    reverseDuration: fast,
    curve: routeFadeCurve,
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
}
