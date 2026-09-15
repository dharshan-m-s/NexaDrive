import 'package:flutter/material.dart';
import 'app_motion.dart';

/// One UI page transition.
///
/// Spatially continuous and restrained: the incoming page glides up a few
/// points while cross-fading, and the outgoing page settles back — the
/// destination feels connected to the source, never like a hard swap.
/// Honors reduced motion by skipping entirely.
class OneUiPageTransitionsBuilder extends PageTransitionsBuilder {
  const OneUiPageTransitionsBuilder();

  static const double _rise = 0.016;
  static const double _settle = 0.008;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (AppMotion.reducedMotion(context)) return child;

    // Secondary: the outgoing page settles down slightly as the primary comes in.
    final secondaryCurve = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
    );
    final settle = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, _settle),
    ).animate(secondaryCurve);

    final primaryCurve = CurvedAnimation(
      parent: animation,
      curve: AppMotion.enter,
      reverseCurve: AppMotion.exit,
    );
    final rise = Tween<Offset>(
      begin: const Offset(0, _rise),
      end: Offset.zero,
    ).animate(primaryCurve);

    return FadeTransition(
      opacity: primaryCurve,
      child: SlideTransition(
        position: rise,
        child: SlideTransition(
          position: settle,
          child: child,
        ),
      ),
    );
  }
}

/// Applies the One UI page transitions for every target platform.
const PageTransitionsTheme kOneUiPageTransitions = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: OneUiPageTransitionsBuilder(),
    TargetPlatform.iOS: OneUiPageTransitionsBuilder(),
    TargetPlatform.linux: OneUiPageTransitionsBuilder(),
    TargetPlatform.windows: OneUiPageTransitionsBuilder(),
    TargetPlatform.macOS: OneUiPageTransitionsBuilder(),
  },
);