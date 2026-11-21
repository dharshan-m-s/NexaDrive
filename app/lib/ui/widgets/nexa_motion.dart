import 'package:flutter/material.dart';

import '../../core/design/app_motion.dart';

/// Passive physical press feedback for an existing control.
///
/// Like [NexaPressable], this never handles the gesture: a [Listener] observes
/// pointer events while taps, long presses, ink and accessibility actions keep
/// flowing to the child. Only the paint transform (and an optional low-alpha
/// tint) responds. Layout, hit area, colour and typography are untouched.
///
/// A press is released when the pointer travels past the touch slop or flicks
/// faster than [AppMotion.pressVelocityThreshold], so a scroll that starts on a
/// button never leaves it compressed. Reduced motion snaps to rest.
class NexaElasticPress extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final bool scale;
  final double pressedScale;
  final Color? tintColor;
  final BorderRadius? borderRadius;

  const NexaElasticPress({
    super.key,
    required this.child,
    this.enabled = true,
    this.scale = true,
    this.pressedScale = AppMotion.pressScale,
    this.tintColor,
    this.borderRadius,
  });

  @override
  State<NexaElasticPress> createState() => _NexaElasticPressState();
}

class _NexaElasticPressState extends State<NexaElasticPress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController.unbounded(
    vsync: this,
    value: 1.0,
    debugLabel: 'NexaElasticPress.press',
  );

  int? _pointer;
  Offset _origin = Offset.zero;
  Duration _downTime = Duration.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reducedMotion(context) && _pointer == null) {
      _press
        ..stop()
        ..value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant NexaElasticPress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _pointer != null) _release();
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _handleDown(PointerDownEvent event) {
    if (!widget.enabled || _pointer != null) return;
    _pointer = event.pointer;
    _origin = event.position;
    _downTime = event.timeStamp;
    _pressTo(widget.pressedScale, AppMotion.elasticPress);
  }

  void _handleMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    final delta = event.position - _origin;
    if (delta.distance > AppMotion.pressTouchSlop ||
        AppMotion.exceedsVelocity(
          delta,
          event.timeStamp - _downTime,
          threshold: AppMotion.pressVelocityThreshold,
        )) {
      _release();
    }
  }

  void _handleUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    _release();
  }

  void _handleCancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _release();
  }

  void _release() {
    _pointer = null;
    _pressTo(1.0, AppMotion.elasticRelease);
  }

  void _pressTo(double target, SpringDescription spring) {
    if (!mounted) return;
    AppMotion.springTo(
      _press,
      target: target,
      spring: spring,
      reducedMotion: AppMotion.reducedMotion(context),
    );
  }

  /// 0 at rest, 1 fully pressed; tint and scale share one physical curve.
  double get _amount {
    final span = 1.0 - widget.pressedScale;
    if (span <= 0) return _pointer == null ? 0.0 : 1.0;
    return ((1.0 - _press.value) / span).clamp(0.0, 1.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.scale && widget.tintColor == null) return widget.child;

    Widget content = widget.child;
    final tint = widget.tintColor;

    if (tint != null) {
      content = AnimatedBuilder(
        animation: _press,
        child: content,
        builder: (context, child) {
          final amount = _amount;
          return Stack(
            fit: StackFit.passthrough,
            children: [
              child!,
              if (amount > 0.001)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: tint.withValues(alpha: tint.a * amount),
                        borderRadius: widget.borderRadius,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      );
    }

    if (widget.scale) {
      content = AnimatedBuilder(
        animation: _press,
        child: content,
        builder: (context, child) =>
            Transform.scale(scale: _press.value, child: child),
      );
    }

    return Listener(
      onPointerDown: _handleDown,
      onPointerMove: _handleMove,
      onPointerUp: _handleUp,
      onPointerCancel: _handleCancel,
      child: RepaintBoundary(child: content),
    );
  }
}

/// Geometry flow used by revealed bars and expanding sections.
///
/// A [SizeTransition] grows the clip rect while a shared fade brings the
/// content in, so neighbouring content makes room instead of jumping. The
/// transition is bounded by [AppMotion.normal].
class NexaFlowTransition extends StatelessWidget {
  final Animation<double> animation;
  final Alignment alignment;
  final Widget child;

  const NexaFlowTransition({
    super.key,
    required this.animation,
    required this.child,
    this.alignment = Alignment.bottomCenter,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ClipRect(
        child: SizeTransition(
          sizeFactor: animation,
          alignment: alignment,
          child: FadeTransition(opacity: animation, child: child),
        ),
      ),
    );
  }
}

/// Shows or hides a section with [NexaFlowTransition].
///
/// Platform reduce swaps instantly. The app-level preference keeps a short
/// fade only, with no geometry movement. The hidden child is removed from the
/// tree, so it cannot hold focus or be announced while collapsed.
class NexaFlowReveal extends StatelessWidget {
  final bool visible;
  final Widget child;
  final Alignment alignment;

  const NexaFlowReveal({
    super.key,
    required this.visible,
    required this.child,
    this.alignment = Alignment.bottomCenter,
  });

  @override
  Widget build(BuildContext context) {
    final systemReduced = AppMotion.systemReducedMotion(context);
    final appReduced = AppMotion.appReducedMotion;
    final duration = systemReduced
        ? Duration.zero
        : appReduced
            ? AppMotion.stateFade
            : AppMotion.normal;
    final reverseDuration = systemReduced
        ? Duration.zero
        : appReduced
            ? AppMotion.stateFade
            : AppMotion.fast;
    final curve = systemReduced || appReduced ? Curves.linear : AppMotion.enter;
    final reverseCurve =
        systemReduced || appReduced ? Curves.linear : AppMotion.exit;

    return AnimatedSwitcher(
      duration: duration,
      reverseDuration: reverseDuration,
      switchInCurve: curve,
      switchOutCurve: reverseCurve,
      transitionBuilder: (child, animation) {
        if (appReduced && !systemReduced) {
          return FadeTransition(opacity: animation, child: child);
        }
        return NexaFlowTransition(
          animation: animation,
          alignment: alignment,
          child: child,
        );
      },
      child: visible
          ? KeyedSubtree(key: const ValueKey('nexa_flow_shown'), child: child)
          : const SizedBox.shrink(key: ValueKey('nexa_flow_hidden')),
    );
  }
}

/// Circular progress that interpolates only between real reported values.
///
/// An unknown ([value] == null) stays indeterminate; no synthetic percentage
/// is ever invented. A determinate value starts at the value reported on the
/// first build and animates only toward newly reported values.
class NexaAnimatedProgress extends StatefulWidget {
  final double? value;
  final double size;
  final double strokeWidth;
  final Color? color;
  final Color? backgroundColor;
  final String? semanticsLabel;

  const NexaAnimatedProgress({
    super.key,
    this.value,
    this.size = 24,
    this.strokeWidth = 2.5,
    this.color,
    this.backgroundColor,
    this.semanticsLabel,
  });

  @override
  State<NexaAnimatedProgress> createState() => _NexaAnimatedProgressState();
}

class _NexaAnimatedProgressState extends State<NexaAnimatedProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    value: (widget.value ?? 0.0).clamp(0.0, 1.0).toDouble(),
    duration: AppMotion.fast,
    vsync: this,
  );

  @override
  void didUpdateWidget(covariant NexaAnimatedProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    final value = widget.value;
    if (value == null) {
      _controller.stop();
      return;
    }
    final target = value.clamp(0.0, 1.0).toDouble();
    if (target == oldWidget.value) return;
    if (AppMotion.reducedMotion(context)) {
      _controller
        ..stop()
        ..value = target;
    } else {
      _controller.animateTo(
        target,
        duration: AppMotion.resolve(context, AppMotion.fast),
        curve: AppMotion.standardCurve,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = widget.color ?? scheme.primary;
    final background = widget.backgroundColor ?? scheme.primaryContainer;

    final Widget indicator;
    if (widget.value == null) {
      indicator = CircularProgressIndicator(
        strokeWidth: widget.strokeWidth,
        strokeCap: StrokeCap.round,
        color: color,
      );
    } else {
      indicator = AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => SizedBox(
          width: widget.size,
          height: widget.size,
          child: CircularProgressIndicator(
            value: _controller.value,
            strokeWidth: widget.strokeWidth,
            strokeCap: StrokeCap.round,
            color: color,
            backgroundColor: background,
          ),
        ),
      );
    }

    final percent =
        widget.value == null ? null : '${(widget.value! * 100).round()}%';
    return RepaintBoundary(
      child: Semantics(
        label: widget.semanticsLabel ?? 'Loading',
        value: percent,
        child: widget.value == null
            ? SizedBox(
                width: widget.size,
                height: widget.size,
                child: indicator,
              )
            : indicator,
      ),
    );
  }
}

/// Small, bounded stagger for one-off section entrances.
///
/// Each child fades from 0.85 and lifts at most [AppMotion.staggerOffset]; the
/// transform is paint-only and returns to zero, so layout never moves. There
/// is no repeat: the controller runs once per widget instance. The last item
/// still finishes inside [AppMotion.staggerDuration].
class NexaStagger extends StatefulWidget {
  final List<Widget> children;
  final Duration step;
  final double offset;

  const NexaStagger({
    super.key,
    required this.children,
    this.step = AppMotion.staggerStep,
    this.offset = AppMotion.staggerOffset,
  });

  @override
  State<NexaStagger> createState() => _NexaStaggerState();
}

class _NexaStaggerState extends State<NexaStagger>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  List<Animation<double>> _items = const [];

  @override
  void initState() {
    super.initState();
    // Inherited widgets are not available until didChangeDependencies; reading
    // MediaQuery here breaks element reuse and can trigger framework asserts.
    _controller = AnimationController(
      duration: AppMotion.staggerDuration,
      value: 0,
      vsync: this,
    );
    _buildItems();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reducedMotion(context)) {
      _controller
        ..stop()
        ..value = 1.0;
    } else if (_controller.value == 0 && !_controller.isAnimating) {
      _controller.forward();
    }
  }

  void _buildItems() {
    final count = widget.children.length.clamp(0, AppMotion.maxStaggerItems);
    final stepRatio =
        (widget.step.inMilliseconds / AppMotion.staggerDuration.inMilliseconds)
            .clamp(0.0, 0.8)
            .toDouble();
    final itemRatio = (AppMotion.staggerItem.inMilliseconds /
            AppMotion.staggerDuration.inMilliseconds)
        .clamp(0.05, 1.0)
        .toDouble();

    _items = List<Animation<double>>.generate(count, (index) {
      final start = (index * stepRatio).clamp(0.0, 0.8).toDouble();
      final end = (start + itemRatio).clamp(start + 0.01, 1.0).toDouble();
      return CurvedAnimation(
        parent: _controller,
        curve: Interval(start, end, curve: AppMotion.enter),
      );
    });
  }

  @override
  void didUpdateWidget(covariant NexaStagger oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.children.length != oldWidget.children.length ||
        widget.step != oldWidget.step) {
      _buildItems();
    }
    if (AppMotion.reducedMotion(context) && _controller.value != 1.0) {
      _controller
        ..stop()
        ..value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The preference is a static notifier, so a live toggle may not call
    // didUpdateWidget. Settle immediately when motion is no longer allowed.
    final reduced = AppMotion.reducedMotion(context);
    if (reduced && _controller.value != 1.0) {
      _controller
        ..stop()
        ..value = 1.0;
    }

    final children = <Widget>[];
    for (var i = 0; i < widget.children.length; i++) {
      Widget child = widget.children[i];
      if (!reduced && i < _items.length) {
        final animation = _items[i];
        child = AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (context, child) => Opacity(
            opacity: 0.85 + 0.15 * animation.value,
            child: Transform.translate(
              offset: Offset(0, (1.0 - animation.value) * widget.offset),
              child: child,
            ),
          ),
        );
      }
      children.add(RepaintBoundary(child: child));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}
