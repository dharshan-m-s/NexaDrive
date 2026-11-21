import 'package:flutter/material.dart';

import 'app_motion.dart';

/// Connected Material 3 page transition.
///
/// Both pages share one short fade while the incoming page eases a fraction
/// into its final scale. There is no horizontal slide on any platform, and the
/// transform is paint-only, so Hero flights keep their measured source and
/// destination rects.
///
/// Platform "disable animations" returns the child immediately. The app-level
/// Reduce animations setting keeps only the short fade; geometry is dropped.
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
    if (AppMotion.systemReducedMotion(context)) return child;

    final incoming = CurvedAnimation(
      parent: animation,
      curve: AppMotion.routeFadeCurve,
      reverseCurve: AppMotion.exit,
    );

    Widget result;
    if (AppMotion.appReducedMotion) {
      result = FadeTransition(opacity: incoming, child: child);
    } else {
      final scale = CurvedAnimation(
        parent: animation,
        curve: AppMotion.routeScaleCurve,
        reverseCurve: AppMotion.routeScaleCurve,
      );
      result = FadeTransition(
        opacity: incoming,
        child: ScaleTransition(
          scale: Tween<double>(
            begin: AppMotion.routeScaleBegin,
            end: 1.0,
          ).animate(scale),
          child: child,
        ),
      );
    }

    // secondaryAnimation is 0 for the topmost route, so the outgoing fade must
    // be inverted: 1 when nothing is above us, 0 when a route covers us.
    final outgoing = CurvedAnimation(
      parent: secondaryAnimation,
      curve: AppMotion.exit,
      reverseCurve: AppMotion.enter,
    );
    return FadeTransition(
      opacity: Tween<double>(
        begin: 1.0,
        end: AppMotion.routeFadeOutEnd,
      ).animate(outgoing),
      child: result,
    );
  }
}

/// Applies the connected transition to every target platform so mobile and
/// desktop share one motion language.
const PageTransitionsTheme kNexaPageTransitions = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: NexaPageTransitionsBuilder(),
    TargetPlatform.iOS: NexaPageTransitionsBuilder(),
    TargetPlatform.linux: NexaPageTransitionsBuilder(),
    TargetPlatform.windows: NexaPageTransitionsBuilder(),
    TargetPlatform.macOS: NexaPageTransitionsBuilder(),
  },
);
