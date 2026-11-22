import 'package:flutter/material.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_motion.dart';
import '../../core/design/app_typography.dart';
import 'nexa_motion.dart';

/// Cross-fades between mutually exclusive page bodies — loading to content,
/// content to error — so a resolved request settles in place instead of
/// swapping the screen out from under the reader.
///
/// Give [stateKey] a value that identifies the state (for example
/// `const ValueKey('empty')`). It must change only when the body actually
/// changes, so paging between records never re-triggers the fade.
///
/// Layout is passed through untouched: each state receives exactly the
/// constraints it would have got standing alone, so a state that fills a scroll
/// region keeps filling it and nothing grows or shrink-wraps unexpectedly.
/// Platform reduce swaps instantly; the app-level setting leaves a short fade.
class NexaStateSwitcher extends StatelessWidget {
  const NexaStateSwitcher({
    super.key,
    required this.stateKey,
    required this.child,
  });

  /// Identifies the current state; changes retrigger the cross-fade.
  final Key stateKey;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.resolveStateChange(context, AppMotion.normal),
      switchInCurve: AppMotion.resolveCurve(context, AppMotion.enter),
      switchOutCurve: AppMotion.resolveCurve(context, AppMotion.exit),
      reverseDuration: AppMotion.resolveStateChange(context, AppMotion.fast),
      layoutBuilder: (currentChild, previousChildren) => Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      ),
      child: KeyedSubtree(key: stateKey, child: child),
    );
  }
}

/// Standard loading block with reserved space.
class NexaLoadingBlock extends StatelessWidget {
  final String? label;
  final double inset;
  final double size;

  const NexaLoadingBlock({
    super.key,
    this.label,
    this.inset = AppDimens.space48,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: inset),
      child: Center(
        child: label == null
            ? NexaAnimatedProgress(size: size)
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  NexaAnimatedProgress(size: size),
                  const SizedBox(height: AppDimens.space12),
                  Text(
                    label!,
                    style: AppTextStyle.bodySmall.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Full-viewport loading state — a centered spinner that fills the space
/// below a page header without reflowing when content arrives.
class NexaLoadingState extends StatelessWidget {
  final String? label;

  const NexaLoadingState({super.key, this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const NexaAnimatedProgress(),
          if (label != null) ...[
            const SizedBox(height: AppDimens.space12),
            Text(
              label!,
              style: AppTextStyle.bodySmall.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Skeleton loader for list items.
class NexaSkeletonList extends StatelessWidget {
  final int itemCount;
  final double height;
  final bool showLeading;
  final bool showTrailing;

  /// Bottom scroll clearance, so the last skeleton row never hides behind the
  /// floating navigation pill.
  final EdgeInsetsGeometry padding;

  const NexaSkeletonList({
    super.key,
    this.itemCount = 5,
    this.height = AppDimens.listHeightLarge,
    this.showLeading = true,
    this.showTrailing = false,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final baseColor = scheme.surfaceContainerHighest;
    final highlightColor = scheme.onSurface.withValues(
      alpha: scheme.brightness == Brightness.dark ? 0.08 : 0.06,
    );

    return ListView.builder(
      // The skeleton is a fixed-size placeholder inside a page scroll view,
      // never an independent scroller. Shrink wrapping keeps it from demanding
      // an unbounded height when it is used as a sliver child.
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      itemCount: itemCount,
      itemBuilder: (context, index) => _SkeletonItem(
        height: height,
        showLeading: showLeading,
        showTrailing: showTrailing,
        baseColor: baseColor,
        highlightColor: highlightColor,
      ),
    );
  }
}

class _SkeletonItem extends StatefulWidget {
  final double height;
  final bool showLeading;
  final bool showTrailing;
  final Color baseColor;
  final Color highlightColor;

  const _SkeletonItem({
    required this.height,
    required this.showLeading,
    required this.showTrailing,
    required this.baseColor,
    required this.highlightColor,
  });

  @override
  State<_SkeletonItem> createState() => _SkeletonItemState();
}

class _SkeletonItemState extends State<_SkeletonItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    // One bounded settle on appearance replaces the old endless shimmer. The
    // placeholders stay legible at every frame and cost no ongoing ticks.
    _controller = AnimationController(
      duration: AppMotion.fast,
      vsync: this,
    );
    _animation = Tween(begin: 0.6, end: 0.8).animate(
      CurvedAnimation(parent: _controller, curve: AppMotion.standardCurve),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reducedMotion(context)) {
      _controller.stop();
      _controller.value = 1.0;
      _settled = true;
    } else if (!_settled) {
      _settled = true;
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return Container(
            height: widget.height,
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.pageMargin,
              vertical: AppDimens.space8,
            ),
            child: Row(
              children: [
                if (widget.showLeading) ...[
                  Container(
                    width: AppDimens.iconTileLarge,
                    height: AppDimens.iconTileLarge,
                    decoration: BoxDecoration(
                      color: Color.lerp(widget.baseColor, widget.highlightColor,
                          _animation.value),
                      borderRadius:
                          BorderRadius.circular(AppDimens.radiusMedium),
                    ),
                  ),
                  const SizedBox(width: AppDimens.space12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 120,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Color.lerp(widget.baseColor,
                              widget.highlightColor, _animation.value),
                          borderRadius:
                              BorderRadius.circular(AppDimens.radiusExtraSmall),
                        ),
                      ),
                      const SizedBox(height: AppDimens.space4),
                      Container(
                        width: 80,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Color.lerp(widget.baseColor,
                              widget.highlightColor, _animation.value * 0.7),
                          borderRadius:
                              BorderRadius.circular(AppDimens.radiusExtraSmall),
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.showTrailing) ...[
                  const SizedBox(width: AppDimens.space12),
                  Container(
                    width: AppDimens.iconMedium,
                    height: AppDimens.iconMedium,
                    decoration: BoxDecoration(
                      color: Color.lerp(widget.baseColor, widget.highlightColor,
                          _animation.value),
                      borderRadius:
                          BorderRadius.circular(AppDimens.radiusStandard),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Skeleton loader for grid items.
class NexaSkeletonGrid extends StatelessWidget {
  final int itemCount;
  final double itemWidth;

  const NexaSkeletonGrid({
    super.key,
    this.itemCount = 6,
    this.itemWidth = 170,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final baseColor = scheme.surfaceContainerHighest;
    final highlightColor = scheme.onSurface.withValues(
      alpha: scheme.brightness == Brightness.dark ? 0.08 : 0.06,
    );

    return GridView.builder(
      padding: const EdgeInsets.all(AppDimens.pageMargin),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount:
            (MediaQuery.sizeOf(context).width / itemWidth).floor().clamp(2, 6),
        mainAxisSpacing: AppDimens.space12,
        crossAxisSpacing: AppDimens.space12,
        childAspectRatio: 0.95,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) => _SkeletonGridItem(
        baseColor: baseColor,
        highlightColor: highlightColor,
      ),
    );
  }
}

class _SkeletonGridItem extends StatefulWidget {
  final Color baseColor;
  final Color highlightColor;

  const _SkeletonGridItem({
    required this.baseColor,
    required this.highlightColor,
  });

  @override
  State<_SkeletonGridItem> createState() => _SkeletonGridItemState();
}

class _SkeletonGridItemState extends State<_SkeletonGridItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    // One bounded settle on appearance replaces the old endless shimmer. The
    // placeholders stay legible at every frame and cost no ongoing ticks.
    _controller = AnimationController(
      duration: AppMotion.fast,
      vsync: this,
    );
    _animation = Tween(begin: 0.6, end: 0.8).animate(
      CurvedAnimation(parent: _controller, curve: AppMotion.standardCurve),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reducedMotion(context)) {
      _controller.stop();
      _controller.value = 1.0;
      _settled = true;
    } else if (!_settled) {
      _settled = true;
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
            ),
            padding: const EdgeInsets.all(AppDimens.space12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Color.lerp(widget.baseColor, widget.highlightColor,
                        _animation.value),
                    borderRadius:
                        BorderRadius.circular(AppDimens.radiusStandard),
                  ),
                ),
                const Spacer(),
                Container(
                  width: double.infinity,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Color.lerp(widget.baseColor, widget.highlightColor,
                        _animation.value),
                    borderRadius:
                        BorderRadius.circular(AppDimens.radiusExtraSmall),
                  ),
                ),
                const SizedBox(height: AppDimens.space4),
                Container(
                  width: 60,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Color.lerp(widget.baseColor, widget.highlightColor,
                        _animation.value * 0.7),
                    borderRadius:
                        BorderRadius.circular(AppDimens.radiusExtraSmall),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
