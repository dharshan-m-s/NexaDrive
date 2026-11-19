import 'package:flutter/material.dart';

/// Compatibility physics alias. Material 3 uses clamping physics with the
/// platform overscroll indicator; the old elastic behavior is intentionally
/// gone, but the type name stays so callers do not break.
class NexaElasticScrollPhysics extends ClampingScrollPhysics {
  const NexaElasticScrollPhysics({super.parent});

  @override
  NexaElasticScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      NexaElasticScrollPhysics(parent: buildParent(ancestor));
}

/// Global scroll configuration — framework defaults, identical across the
/// single Flutter codebase. Touch platforms show the Material overscroll glow;
/// desktop keeps its native scrollbars.
class NexaScrollBehavior extends MaterialScrollBehavior {
  const NexaScrollBehavior();
}
