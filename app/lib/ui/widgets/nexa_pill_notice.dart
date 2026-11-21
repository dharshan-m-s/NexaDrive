import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/design/app_dimensions.dart';
import '../../core/design/app_motion.dart';
import '../../core/design/app_shadows.dart';
import '../../core/design/app_typography.dart';

/// A short-lived status surface that lives inside the floating pill's bounds.
///
/// Notices are not routes and carry no scrim: they replace the pill's content
/// for a moment, then return navigation immediately. Horizontal or downward
/// swipes dismiss early; reduced motion turns the transition into an instant
/// cross-fade.
class NexaPillNotice extends StatefulWidget {
  const NexaPillNotice({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.onDismissed,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onDismissed;

  /// Two ambient beats: long enough to read, short enough not to feel modal.
  static final Duration autoDismissDelay = AppMotion.ambient * 2;

  @override
  State<NexaPillNotice> createState() => _NexaPillNoticeState();
}

class _NexaPillNoticeState extends State<NexaPillNotice> {
  Timer? _dismissTimer;
  Timer? _exitTimer;
  bool _visible = true;
  bool _exitCompleted = false;
  Offset _drag = Offset.zero;

  @override
  void initState() {
    super.initState();
    _armTimer();
  }

  @override
  void didUpdateWidget(covariant NexaPillNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message ||
        oldWidget.actionLabel != widget.actionLabel ||
        oldWidget.onAction != widget.onAction) {
      _exitTimer?.cancel();
      _visible = true;
      _exitCompleted = false;
      _drag = Offset.zero;
      _armTimer();
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _exitTimer?.cancel();
    super.dispose();
  }

  void _armTimer() {
    _dismissTimer?.cancel();
    _dismissTimer = Timer(NexaPillNotice.autoDismissDelay, _dismiss);
  }

  void _dismiss() {
    if (!mounted || !_visible) return;
    _dismissTimer?.cancel();
    setState(() => _visible = false);
    _exitTimer?.cancel();
    _exitTimer = Timer(AppMotion.resolve(context, AppMotion.fast), () {
      if (!mounted) return;
      setState(() => _exitCompleted = true);
      widget.onDismissed?.call();
    });
  }

  void _onDragStart(DragStartDetails _) {
    // A notice the user is interacting with should not expire under their hand.
    _dismissTimer?.cancel();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_visible) return;
    setState(() => _drag = Offset(_drag.dx + details.delta.dx, 0));
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (!_visible || details.delta.dy <= 0) return;
    setState(() => _drag = Offset(0, _drag.dy + details.delta.dy));
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_drag.dx.abs() >= AppDimens.bottomNavHeight) {
      _dismiss();
      return;
    }
    _settle();
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_drag.dy >= AppDimens.bottomNavHeight / 2) {
      _dismiss();
      return;
    }
    _settle();
  }

  void _settle() {
    if (!mounted || !_visible) return;
    // No spring for a rejected swipe: the notice is transient chrome, and a
    // large animation here would keep it on screen longer than its lifetime.
    setState(() => _drag = Offset.zero);
    _armTimer();
  }

  void _runAction() {
    widget.onAction?.call();
    _dismiss();
  }

  @override
  Widget build(BuildContext context) {
    if (_exitCompleted) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final reduced = AppMotion.reducedMotion(context);
    final duration = AppMotion.resolve(context, AppMotion.fast);
    final radius = BorderRadius.circular(AppDimens.radiusPill);

    final surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: AppShadows.floatingPill(scheme.brightness),
      ),
      child: Material(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: scheme.shadow,
        shape: RoundedRectangleBorder(borderRadius: radius),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: AppDimens.bottomNavHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.space16,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    container: true,
                    liveRegion: true,
                    label: widget.message,
                    explicitChildNodes: true,
                    child: Text(
                      widget.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.labelMedium.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ),
                if (widget.actionLabel != null) ...[
                  const SizedBox(width: AppDimens.space8),
                  TextButton(
                    onPressed: _runAction,
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.primary,
                      minimumSize: const Size(
                        AppDimens.touchTarget,
                        AppDimens.touchTarget,
                      ),
                    ),
                    child: Text(widget.actionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: duration,
      curve: AppMotion.curveFor(context, AppMotion.exit),
      child: AnimatedSlide(
        offset: _visible || reduced ? Offset.zero : const Offset(0, 0.08),
        duration: duration,
        curve: AppMotion.curveFor(context, AppMotion.exit),
        child: Transform.translate(
          offset: _drag,
          child: IgnorePointer(
            ignoring: !_visible,
            child: GestureDetector(
              onHorizontalDragStart: _onDragStart,
              onHorizontalDragUpdate: _onHorizontalDragUpdate,
              onHorizontalDragEnd: _onHorizontalDragEnd,
              onVerticalDragStart: _onDragStart,
              onVerticalDragUpdate: _onVerticalDragUpdate,
              onVerticalDragEnd: _onVerticalDragEnd,
              child: Semantics(
                hint: 'Swipe to dismiss',
                child: surface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
