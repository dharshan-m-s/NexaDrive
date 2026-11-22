import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/design/app_motion.dart';

/// Snaps a page that owns its slivers to the floating header's edge.
///
/// A floating header can only disappear once the scroll offset reaches its full
/// extent, which includes the system top inset. Without this coordinator a
/// short drag parks the chrome over the status bar. Moving the scroll position
/// to the header edge on release hides it completely without changing layout.
class NexaHeaderSnapScrollView extends StatefulWidget {
  const NexaHeaderSnapScrollView({
    super.key,
    required this.headerExtent,
    required this.slivers,
    this.onRefresh,
  });

  final double headerExtent;
  final List<Widget> slivers;
  final RefreshCallback? onRefresh;

  @override
  State<NexaHeaderSnapScrollView> createState() =>
      _NexaHeaderSnapScrollViewState();
}

class _NexaHeaderSnapScrollViewState extends State<NexaHeaderSnapScrollView> {
  final ScrollController _controller = ScrollController();
  double _startPixels = 0;
  double _lastPixels = 0;
  ScrollDirection _lastDirection = ScrollDirection.idle;

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
      _lastPixels = notification.metrics.pixels;
      _lastDirection = ScrollDirection.idle;
      return false;
    }

    if (notification is ScrollUpdateNotification) {
      if (_settling) return false;
      final delta = notification.metrics.pixels - _lastPixels;
      if (delta.abs() > 0.5) {
        _lastDirection =
            delta > 0 ? ScrollDirection.reverse : ScrollDirection.forward;
        _lastPixels = notification.metrics.pixels;
      }
      return false;
    }

    if (notification is ScrollEndNotification && _controller.hasClients) {
      if (_settling || !_userDriven) {
        _settling = false;
        _userDriven = false;
        _lastPixels = _controller.position.pixels;
        _lastDirection = ScrollDirection.idle;
        return false;
      }
      final hidden = widget.headerExtent.clamp(
        0.0,
        _controller.position.maxScrollExtent,
      );
      final current = _controller.position.pixels;
      final direction = _lastDirection == ScrollDirection.idle
          ? (current > _startPixels
              ? ScrollDirection.reverse
              : current < _startPixels
                  ? ScrollDirection.forward
                  : ScrollDirection.idle)
          : _lastDirection;

      // Once the chrome is fully offscreen, a downward gesture is ordinary
      // content scrolling. Snapping it back to the header edge on every release
      // makes the library look stuck and can pull the chrome into view again.
      final double? target;
      if (direction == ScrollDirection.forward) {
        target = 0.0;
      } else if (current >= hidden - 1) {
        target = null;
      } else if (direction == ScrollDirection.reverse || current > hidden / 2) {
        target = hidden;
      } else {
        target = 0.0;
      }
      _lastDirection = ScrollDirection.idle;
      _lastPixels = current;
      if (target != null && (current - target).abs() > 1) {
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
/// body's layout when the gesture ends. The snap itself is driven by the shared
/// scroll position in [NexaHeaderSnapScrollView], which keeps the header and the
/// body in agreement on every platform scroll physics. The top system inset is
/// part of the header surface, so hiding it removes the whole chrome instead of
/// leaving a strip under the status bar.
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

    // The scroll coordinator owns the settle. Flutter's built-in snap animates
    // the header's internal offset separately from the scroll position, and a
    // fling end can make it reveal the surface while the body keeps scrolling.
    return SliverPersistentHeader(
      key: ValueKey<String>('nexa_floating_header_$_generation'),
      floating: true,
      pinned: false,
      delegate: _NexaHeaderDelegate(
        extent: extent,
        vsync: this,
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
    required this.child,
  });

  final double extent;

  @override
  final TickerProvider vsync;

  final Widget child;

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
      oldDelegate.extent != extent || oldDelegate.child != child;
}
