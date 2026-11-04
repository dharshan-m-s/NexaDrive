import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/design/app_motion.dart';

/// Adds spring-driven tactile feedback to an existing control.
///
/// This widget never handles the gesture itself: it observes pointer events
/// with a passive [Listener], so taps, long presses, ink responses and
/// accessibility actions keep flowing to the child unchanged. Layout, hit
/// area, colours and typography are untouched — only the paint transform (and,
/// when a tint is supplied, a translucent overlay) responds to a press.
///
/// The pressed state is cancelled when the pointer travels past [kTouchSlop]
/// or leaves the control, which is what keeps a scroll that starts on a button
/// from leaving the button stuck in its pressed state.
///
/// Reduced motion snaps between states instead of springing.
class NexaPressable extends StatefulWidget {
  final Widget child;

  /// Whether feedback is allowed. Disabled controls stay perfectly still.
  final bool enabled;

  /// Whether the control scales while pressed. Full-width rows should pass
  /// `false` and use [tintColor] instead: shrinking a row exposes its
  /// background and reads as a layout glitch.
  final bool scale;

  /// Scale reached while held. Prefer [AppMotion.pressScale] for controls and
  /// [AppMotion.pressScaleMedia] for artwork.
  final double pressedScale;

  /// Optional press highlight painted over the child. Low alpha values only
  /// (≈0.03–0.06); the colour is applied at its own alpha while pressed.
  final Color? tintColor;

  /// Clip radius for [tintColor].
  final BorderRadius? borderRadius;

  const NexaPressable({
    super.key,
    required this.child,
    this.enabled = true,
    this.scale = true,
    this.pressedScale = AppMotion.pressScale,
    this.tintColor,
    this.borderRadius,
  });

  @override
  State<NexaPressable> createState() => _NexaPressableState();
}

class _NexaPressableState extends State<NexaPressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController.unbounded(
    vsync: this,
    value: 1.0,
    debugLabel: 'NexaPressable.press',
  );

  int? _pointer;
  Offset _origin = Offset.zero;
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = AppMotion.reducedMotion(context);
    // A preference change mid-press must not leave the control scaled down.
    if (_reduced && _pointer == null && _press.value != 1.0) {
      _press.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant NexaPressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _pointer != null) _release();
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  bool get _interactive => widget.enabled;

  void _handleDown(PointerDownEvent event) {
    if (!_interactive || _pointer != null) return;
    _pointer = event.pointer;
    _origin = event.position;
    _pressTo(widget.pressedScale, AppMotion.pressSpring);
  }

  void _handleMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    if ((event.position - _origin).distance > kTouchSlop) _release();
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
    _pressTo(1.0, AppMotion.pressReleaseSpring);
  }

  void _pressTo(double target, SpringDescription spring) {
    if (!mounted) return;
    AppMotion.springTo(
      _press,
      target: target,
      spring: spring,
      reducedMotion: _reduced,
    );
  }

  /// 0 at rest, 1 fully pressed. Used for the optional tint so the highlight
  /// and the scale share one physical curve.
  double get _amount {
    final span = 1.0 - widget.pressedScale;
    if (span <= 0) return _pointer == null ? 0.0 : 1.0;
    return ((1.0 - _press.value) / span).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final tint = widget.tintColor;
    if (!widget.scale && tint == null) return widget.child;

    Widget content = widget.child;

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
      child: content,
    );
  }
}
