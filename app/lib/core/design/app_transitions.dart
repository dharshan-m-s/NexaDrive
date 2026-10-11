import 'package:flutter/material.dart';
import 'app_motion.dart';

/// NexaDrive page transition.
///
/// THE REFERENCE: the iOS interactive push. The incoming page slides in from
/// the trailing edge while the outgoing page recedes with a slight parallax and
/// dim — the destination feels spatially connected to the source, never like a
/// hard swap. Honours reduced motion by skipping the animation entirely.
class NexaPageTransitionsBuilder extends PageTransitionsBuilder {
  const NexaPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (AppMotion.reducedMotion(context)) return child;

    // The outgoing page slides left by a third and dims slightly.
    final secondaryCurve = CurvedAnimation(
      parent: secondaryAnimation,
      curve: AppMotion.standard,
    );
    final outgoingSlide = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-0.3, 0),
    ).animate(secondaryCurve);
    final outgoingFade =
        Tween<double>(begin: 1.0, end: 0.85).animate(secondaryCurve);

    // The incoming page slides in from the right edge.
    final primaryCurve = CurvedAnimation(
      parent: animation,
      curve: AppMotion.enterCurve,
      reverseCurve: AppMotion.exitCurve,
    );
    final incomingSlide = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(primaryCurve);

    return SlideTransition(
      position: outgoingSlide,
      child: FadeTransition(
        opacity: outgoingFade,
        child: SlideTransition(
          position: incomingSlide,
          child: child,
        ),
      ),
    );
  }
}

/// Applies the NexaDrive page transitions for every target platform.
const PageTransitionsTheme kNexaPageTransitions = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: NexaPageTransitionsBuilder(),
    TargetPlatform.iOS: NexaPageTransitionsBuilder(),
    TargetPlatform.linux: NexaPageTransitionsBuilder(),
    TargetPlatform.windows: NexaPageTransitionsBuilder(),
    TargetPlatform.macOS: NexaPageTransitionsBuilder(),
  },
);
