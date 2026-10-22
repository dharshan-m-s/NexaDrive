import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_motion.dart';
import '../../core/design/app_typography.dart';
import 'nexa_progress.dart';

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
/// Reduced motion swaps instantly.
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
      duration: AppMotion.resolve(context, AppMotion.normal),
      switchInCurve: AppMotion.curveFor(context, AppMotion.enter),
      switchOutCurve: AppMotion.curveFor(context, AppMotion.exit),
      reverseDuration: AppMotion.resolve(context, AppMotion.fast),
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
            ? NexaCircularProgress(size: size)
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  NexaCircularProgress(size: size),
                  const SizedBox(height: AppDimens.space12),
                  Text(
                    label!,
                    style: AppTextStyle.caption1.copyWith(
                      color: AppColors.labelSecondaryFor(
                        Theme.of(context).brightness,
                      ),
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
          const NexaCircularProgress(),
          if (label != null) ...[
            const SizedBox(height: AppDimens.space12),
            Text(
              label!,
              style: AppTextStyle.caption1.copyWith(
                color:
                    AppColors.labelSecondaryFor(Theme.of(context).brightness),
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

  const NexaSkeletonList({
    super.key,
    this.itemCount = 5,
    this.height = AppDimens.listHeightLarge,
    this.showLeading = true,
    this.showTrailing = false,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final baseColor = AppColors.fillFor(brightness);
    final highlightColor = brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    return ListView.builder(
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

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
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
                        BorderRadius.circular(AppDimens.radiusStandard),
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
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: AppDimens.space4),
                    Container(
                      width: 80,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Color.lerp(widget.baseColor,
                            widget.highlightColor, _animation.value * 0.7),
                        borderRadius: BorderRadius.circular(4),
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
    final brightness = Theme.of(context).brightness;
    final baseColor = AppColors.fillFor(brightness);
    final highlightColor = brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

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

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceGroupedFor(Theme.of(context).brightness),
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
                  borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
                ),
              ),
              const Spacer(),
              Container(
                width: double.infinity,
                height: 16,
                decoration: BoxDecoration(
                  color: Color.lerp(widget.baseColor, widget.highlightColor,
                      _animation.value),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: AppDimens.space4),
              Container(
                width: 60,
                height: 12,
                decoration: BoxDecoration(
                  color: Color.lerp(widget.baseColor, widget.highlightColor,
                      _animation.value * 0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
