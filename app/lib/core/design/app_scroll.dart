import 'package:flutter/material.dart';

import 'app_motion.dart';

/// NexaDrive's elastic scroll physics.
///
/// iOS scrolls like a rubber band: the content follows the finger past the
/// edge with progressive resistance and returns on a spring. Android's default
/// clamping physics plus the Material stretch indicator reads as a different
/// platform, so the app pins the iOS-style bounce on every touch platform.
///
/// The spring and deceleration come from [AppMotion], keeping the feel in the
/// same token file as every other curve in the product.
class NexaElasticScrollPhysics extends BouncingScrollPhysics {
  const NexaElasticScrollPhysics({
    super.parent,
    super.decelerationRate = ScrollDecelerationRate.normal,
  });

  @override
  SpringDescription get spring => AppMotion.scrollSpring;

  @override
  NexaElasticScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      NexaElasticScrollPhysics(
        parent: buildParent(ancestor),
        decelerationRate: decelerationRate,
      );
}

/// Global scroll configuration.
///
/// Touch platforms (Android, iOS, Fuchsia) get [NexaElasticScrollPhysics] and
/// drop the Material overscroll indicator, since the bounce already provides
/// the edge feedback and the two effects would double up. Desktop keeps the
/// framework defaults: clamping on Linux/Windows, fast bouncing on macOS, and
/// the platform scrollbars that come with them.
///
/// When the platform asks for reduced motion the bounce is replaced by
/// clamping, so the viewport moves only while the finger (or wheel) does.
class NexaScrollBehavior extends MaterialScrollBehavior {
  const NexaScrollBehavior();

  /// Platforms where dragging past the edge should stretch and settle back.
  static const Set<TargetPlatform> elasticPlatforms = {
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.fuchsia,
  };

  bool _elastic(BuildContext context) =>
      elasticPlatforms.contains(getPlatform(context));

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    if (!_elastic(context)) return super.getScrollPhysics(context);

    final reducedMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reducedMotion) {
      return const ClampingScrollPhysics(
        parent: RangeMaintainingScrollPhysics(),
      );
    }
    return const NexaElasticScrollPhysics(
      parent: RangeMaintainingScrollPhysics(),
    );
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // On touch platforms the rubber-band edge is the feedback; the Material
    // stretch/glow would be a second, competing effect.
    if (_elastic(context)) return child;
    return super.buildOverscrollIndicator(context, child, details);
  }
}
