import 'package:flutter/material.dart';

/// Material 3 page transition: the incoming page fades and moves forward
/// slightly while the outgoing page dims. No horizontal slide, no parallax.
class NexaPageTransitionsBuilder extends FadeForwardsPageTransitionsBuilder {
  const NexaPageTransitionsBuilder();
}

/// Applies the Material 3 transition to every target platform so the app feels
/// identical on mobile and desktop.
const PageTransitionsTheme kNexaPageTransitions = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: NexaPageTransitionsBuilder(),
    TargetPlatform.iOS: NexaPageTransitionsBuilder(),
    TargetPlatform.linux: NexaPageTransitionsBuilder(),
    TargetPlatform.windows: NexaPageTransitionsBuilder(),
    TargetPlatform.macOS: NexaPageTransitionsBuilder(),
  },
);
