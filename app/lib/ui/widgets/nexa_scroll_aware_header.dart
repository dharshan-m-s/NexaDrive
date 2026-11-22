import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/design/app_motion.dart';

/// Completes the floating header's hide near the very top of a scroll view.
///
/// Flutter's floating sliver already snaps the chrome alone while the body is
/// past the header band; that is what keeps a deep Files/Photos scroll in place
/// when the top bar returns. The sliver cannot hide fully before the scroll
/// offset reaches its own extent, so this coordinator only settles the position
/// while it is still inside that short band. It never drags a deep list back to
/// offset zero.
class NexaHeaderSnapScrollView extends StatefulWidget {
  const NexaHeaderSnapScrollView({
    super.key,
    required this.headerExtent,
    required this.slivers,
    this.onRefresh,
    this.physics,
  });

  final double headerExtent;
  final List<Widget> slivers;
  final RefreshCallback? onRefresh;

  /// Optional scroll physics for pages that need a specific edge feel, such as
  /// the Files list's elastic overscroll. The header coordinator leaves
  /// out-of-range settles to the physics so the rubber band is not cut short.
  final ScrollPhysics? physics;

  @override
  State<NexaHeaderSnapScrollView> createState() =>
      _NexaHeaderSnapScrollViewState();
}

class _NexaHeaderSnapScrollViewState extends State<NexaHeaderSnapScrollView> {
  final ScrollController _controller = ScrollController();
  double _startPixels = 0;

  /// The settle is a programmatic scroll. Its end notification must not be
  /// mistaken for a new user gesture, or a long downward drag would reveal the
  /// chrome again while the settle moves the position back to the header edge.
  bool _settling = false;

  /// Flutter reports drag-backed gestures on [ScrollStartNotification]. Ballistic
  /// overscroll bounces and programmatic settles start without drag details and
  /// must not be treated as the user asking to reveal the chrome.
  bool _userDriven = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _onNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      final userDriven = notification.dragDetails != null;
      if (_settling && !userDriven) {
        _userDriven = false;
        return false;
      }
      _settling = false;
      _userDriven = userDriven;
      _startPixels = notification.metrics.pixels;
      return false;
    }

    if (notification is ScrollEndNotification && _controller.hasClients) {
      if (_settling || !_userDriven) {
        _settling = false;
        _userDriven = false;
        return false;
      }
      // Elastic physics owns its own return from an edge. Animating the header
      // to an in-range target here would cancel the rubber band mid-flight.
      if (_controller.position.outOfRange) {
        _userDriven = false;
        return false;
      }
      final position = _controller.position;
      final edge = widget.headerExtent.clamp(0.0, position.maxScrollExtent);
      final current = position.pixels;

      // Past the header band Flutter's native floating snap animates only the
      // chrome. Touching the scroll position here would yank a deep list back
      // towards the top every time the user asked for the top bar.
      if (current >= edge - 1) {
        _userDriven = false;
        return false;
      }

      // Inside the band there is not enough scroll range for the native sliver
      // to hide completely. A short position settle finishes that one case.
      final net = current - _startPixels;
      final target = net > edge / 3 ? edge : 0.0;
      if ((current - target).abs() > 1) {
        final settleTarget = target;
        _settling = true;
        final duration = AppMotion.resolve(context, AppMotion.headerSettle);
        // A scroll position is still finishing its drag activity while this
        // notification is dispatched. Starting the settle on the next frame
        // keeps it from being discarded as a late drag update.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_controller.hasClients) return;
          _controller.animateTo(
            settleTarget,
            duration: duration,
            curve: AppMotion.headerRevealCurve,
          );
        });
      }
      _userDriven = false;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    Widget view = CustomScrollView(
      controller: _controller,
      physics: widget.physics,
      clipBehavior: Clip.hardEdge,
      slivers: widget.slivers,
    );
    if (widget.onRefresh != null) {
      view = RefreshIndicator(onRefresh: widget.onRefresh!, child: view);
    }
    return NotificationListener<ScrollNotification>(
      onNotification: _onNotification,
      child: view,
    );
  }
}

/// Broadcasts a token whenever the shell switches destinations.
///
/// Pages stay alive in the shell's `IndexedStack`, so a floating header's
/// hidden state would otherwise survive a tab switch. Listening to this token
/// restores the chrome on entry without rebuilding the page's content.
class NexaHeaderResetScope extends InheritedNotifier<ValueNotifier<int>> {
  const NexaHeaderResetScope({
    super.key,
    required ValueNotifier<int> notifier,
    required super.child,
  }) : super(notifier: notifier);

  static ValueNotifier<int>? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<NexaHeaderResetScope>()
      ?.notifier;
}

/// A Material 3 floating header for use as the first sliver of a scroll view.
///
/// The geometry is owned by Flutter's `RenderSliverFloatingPersistentHeader`
/// (`floating: true`, `pinned: false`). That is the same render object behind
/// `SliverAppBar`, so the surface tracks the finger 1:1 and never changes the
/// body's layout when the gesture ends. Its native snap animation moves only
/// the header, not the list offset. [NexaHeaderSnapScrollView] settles the
/// position only in the short band before the header can hide on its own. The
/// top system inset is part of the header surface, so hiding it removes the
/// whole chrome instead of leaving a strip under the status bar.
class NexaScrollAwareHeader extends StatefulWidget {
  const NexaScrollAwareHeader({
    super.key,
    required this.header,
    this.backgroundColor,
    this.initialContentExtent = 168,
  });

  /// The chrome that floats away. It stays mounted while offscreen.
  final Widget header;

  /// Surface behind the header. Keeps it fully opaque while it overlaps content.
  final Color? backgroundColor;

  /// Starting measurement until the real header reports its natural height.
  final double initialContentExtent;

  @override
  State<NexaScrollAwareHeader> createState() => _NexaScrollAwareHeaderState();
}

class _NexaScrollAwareHeaderState extends State<NexaScrollAwareHeader>
    with SingleTickerProviderStateMixin {
  /// Recreating the sliver on page entry clears Flutter's internal floating
  /// state. The scroll position is reset first, so the new sliver starts at
  /// offset zero and paints the full header.
  int _generation = 0;

  ValueNotifier<int>? _resetNotifier;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notifier = NexaHeaderResetScope.maybeOf(context);
    if (identical(notifier, _resetNotifier)) return;
    _resetNotifier?.removeListener(_showHeader);
    _resetNotifier = notifier;
    _resetNotifier?.addListener(_showHeader);
  }

  @override
  void dispose() {
    _resetNotifier?.removeListener(_showHeader);
    super.dispose();
  }

  /// Restores the full chrome when the shell reveals this destination again.
  void _showHeader() {
    if (!mounted) return;
    final nested = context.findAncestorStateOfType<NestedScrollViewState>();
    if (nested != null) {
      // Inner position drives the outer one, so reset it first. Jumping only
      // the outer position would reveal the chrome over a scrolled body.
      final inner = nested.innerController;
      if (inner.hasClients) inner.jumpTo(inner.position.minScrollExtent);
      final outer = nested.outerController;
      if (outer.hasClients) outer.jumpTo(outer.position.minScrollExtent);
    } else {
      final scrollable = Scrollable.maybeOf(context);
      if (scrollable != null) {
        scrollable.position.jumpTo(scrollable.position.minScrollExtent);
      }
    }
    setState(() => _generation++);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final topInset = MediaQuery.paddingOf(context).top;
    final extent = topInset + widget.initialContentExtent;

    // Native snap owns the chrome after the header band. It is deliberately
    // enabled here: animating the scroll position instead would teleport a deep
    // Files/Photos list back to the top whenever the user asked for the bar.
    return SliverPersistentHeader(
      key: ValueKey<String>('nexa_floating_header_$_generation'),
      floating: true,
      pinned: false,
      delegate: _NexaHeaderDelegate(
        extent: extent,
        vsync: this,
        snap: AppMotion.headerSnapFor(context),
        child: Material(
          key: const ValueKey<String>('nexa_scroll_aware_header'),
          color: widget.backgroundColor ?? scheme.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shadowColor: Colors.transparent,
          clipBehavior: Clip.hardEdge,
          child: Padding(
            padding: EdgeInsets.only(top: topInset),
            child: SizedBox(
              key: const ValueKey<String>('nexa_scroll_aware_header_content'),
              width: double.infinity,
              child: widget.header,
            ),
          ),
        ),
      ),
    );
  }
}

class _NexaHeaderDelegate extends SliverPersistentHeaderDelegate {
  _NexaHeaderDelegate({
    required this.extent,
    required this.vsync,
    required FloatingHeaderSnapConfiguration snap,
    required this.child,
  }) : _snap = snap;

  final double extent;

  @override
  final TickerProvider vsync;

  final FloatingHeaderSnapConfiguration _snap;
  final Widget child;

  @override
  FloatingHeaderSnapConfiguration get snapConfiguration => _snap;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) =>
      SizedBox(
        width: double.infinity,
        height: extent,
        child: child,
      );

  @override
  bool shouldRebuild(covariant _NexaHeaderDelegate oldDelegate) =>
      oldDelegate.extent != extent ||
      oldDelegate.child != child ||
      oldDelegate._snap.curve != _snap.curve ||
      oldDelegate._snap.duration != _snap.duration;
}
