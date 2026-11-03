import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/physics.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_motion.dart';
import '../../core/design/app_typography.dart';
import 'nexa_liquid_glass.dart';

/// Floating Liquid Glass navigation dock.
///
/// The dock is intentionally the one continuously refracted surface in the
/// shell. A clipped backdrop, theme-aware tint, directional highlight,
/// hairline edge and soft shadow create depth without frosting page content.
/// The selected tab travels on a spring and stretches subtly before settling.
class NexaBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<NexaBottomNavItem> items;

  const NexaBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final accent = AppColors.accentFor(brightness);
    final itemCount = items.length;
    final activeIndex =
        itemCount == 0 ? 0 : currentIndex.clamp(0, itemCount - 1);
    final activeCenter =
        itemCount == 0 ? 0.0 : -1.0 + ((activeIndex + 0.5) * 2.0 / itemCount);

    return SizedBox(
      height: AppDimens.bottomNavHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
        // Subtle reflected colour lives behind the capsule, not on top of it.
        // The glass shader refracts this and the page underneath together.
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(activeCenter, -0.45),
                  radius: 1.05,
                  colors: [
                    accent.withValues(
                        alpha: brightness == Brightness.dark ? 0.15 : 0.10),
                    const Color(0xFF52C7D8).withValues(alpha: 0.045),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.46, 1],
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: NexaLiquidGlass(
            borderRadius: BorderRadius.circular(AppDimens.radiusPill),
            blurSigma: 1.35,
            tintOpacity: brightness == Brightness.dark ? 0.095 : 0.07,
            refractionHeight: 18,
            refractionAmount: -36,
            depthEffect: 1.0,
            chromaticDispersion: 1.9,
            padding: EdgeInsets.zero,
            child: SizedBox(
              width: double.infinity,
              height: AppDimens.bottomNavHeight,
              child: _NavRow(
                items: items,
                currentIndex: currentIndex,
                onTap: onTap,
              ),
            ),
          ),
        ),
        ],
      ),
    );
  }
}

class _NavRow extends StatefulWidget {
  final List<NexaBottomNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _NavRow({
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  State<_NavRow> createState() => _NavRowState();
}

class _NavRowState extends State<_NavRow> with SingleTickerProviderStateMixin {
  late final AnimationController _selection = AnimationController.unbounded(
    vsync: this,
    value: _safeIndex(widget.currentIndex).toDouble(),
    debugLabel: 'NexaBottomNav.selection',
  );

  int _safeIndex(int index) {
    if (widget.items.isEmpty) return 0;
    return index.clamp(0, widget.items.length - 1);
  }

  @override
  void didUpdateWidget(covariant _NavRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex ||
        oldWidget.items.length != widget.items.length) {
      _moveSelection();
    }
  }

  void _moveSelection() {
    final target = _safeIndex(widget.currentIndex).toDouble();
    if (AppMotion.reducedMotion(context)) {
      _selection
        ..stop()
        ..value = target;
      return;
    }
    _selection.animateWith(
      SpringSimulation(
        AppMotion.glassSpring,
        _selection.value,
        target,
        _selection.velocity,
      ),
    );
  }

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final count = items.length;
        final itemWidth = constraints.maxWidth / count;
        const horizontalInset = 5.0;
        const indicatorHeight = 48.0;
        final indicatorWidth =
            (itemWidth - horizontalInset * 2).clamp(0.0, itemWidth);

        return AnimatedBuilder(
          animation: _selection,
          builder: (context, _) {
            final selectedPosition =
                _selection.value.clamp(0.0, (count - 1).toDouble());
            final velocity = _selection.isAnimating ? _selection.velocity : 0.0;
            final stretch = (velocity.abs() / 80.0).clamp(0.0, 0.16);
            final left =
                selectedPosition * itemWidth + (itemWidth - indicatorWidth) / 2;

            return Stack(
              fit: StackFit.expand,
              children: [
                if (widget.currentIndex >= 0 && widget.currentIndex < count)
                  Positioned(
                    left: left,
                    top: (AppDimens.bottomNavHeight - indicatorHeight) / 2,
                    width: indicatorWidth,
                    height: indicatorHeight,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.diagonal3Values(
                        1 + stretch,
                        1 - stretch * 0.45,
                        1,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(AppDimens.radiusPill),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppColors.accentFor(brightness).withValues(
                                alpha:
                                    brightness == Brightness.dark ? 0.15 : 0.10,
                              ),
                              AppColors.accentFor(brightness).withValues(
                                alpha: brightness == Brightness.dark
                                    ? 0.04
                                    : 0.025,
                              ),
                            ],
                          ),
                          border: Border.all(
                            color: AppColors.accentFor(brightness).withValues(
                              alpha:
                                  brightness == Brightness.dark ? 0.28 : 0.20,
                            ),
                            width: 0.7,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.accentFor(brightness).withValues(
                                alpha: brightness == Brightness.dark
                                    ? 0.075
                                    : 0.045,
                              ),
                              blurRadius: 12,
                              spreadRadius: -7,
                            ),
                          ],
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                Row(
                  children: List.generate(count, (index) {
                    return Expanded(
                      child: _NavItem(
                        item: items[index],
                        isSelected: index == widget.currentIndex,
                        onTap: () => widget.onTap(index),
                        brightness: brightness,
                      ),
                    );
                  }),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _NavItem extends StatelessWidget {
  final NexaBottomNavItem item;
  final bool isSelected;
  final VoidCallback onTap;
  final Brightness brightness;

  const _NavItem({
    required this.item,
    required this.isSelected,
    required this.onTap,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = brightness == Brightness.dark
        ? Colors.white
        : AppColors.accentTextFor(brightness);
    final inactiveColor = AppColors.textSecondaryFor(brightness).withValues(
      alpha: brightness == Brightness.dark ? 0.78 : 0.72,
    );

    return Semantics(
      button: true,
      selected: isSelected,
      label: item.label,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () {
            if (!isSelected) unawaited(HapticFeedback.selectionClick());
            onTap();
          },
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
          child: SizedBox(
            height: AppDimens.bottomNavHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.space2,
                vertical: AppDimens.space6,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(
                    duration: AppMotion.resolve(context, AppMotion.fast),
                    switchInCurve: AppMotion.curveFor(context, AppMotion.enter),
                    switchOutCurve: AppMotion.curveFor(context, AppMotion.exit),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.82, end: 1.0)
                            .animate(animation),
                        child: child,
                      ),
                    ),
                    child: Icon(
                      isSelected ? item.selectedIcon : item.icon,
                      key: ValueKey<bool>(isSelected),
                      size: 22,
                      color: isSelected ? activeColor : inactiveColor,
                    ),
                  ),
                  const SizedBox(height: AppDimens.space2),
                  AnimatedDefaultTextStyle(
                    duration: AppMotion.resolve(context, AppMotion.fast),
                    curve: AppMotion.curveFor(context, AppMotion.standardCurve),
                    style: AppTextStyle.navLabel.copyWith(
                      fontSize: 10.5,
                      color: isSelected ? activeColor : inactiveColor,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                    ),
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom navigation item definition.
class NexaBottomNavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const NexaBottomNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

/// Standard NexaDrive bottom navigation items.
class NexaBottomNavItems {
  static const List<NexaBottomNavItem> primary = [
    NexaBottomNavItem(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      label: 'Home',
    ),
    NexaBottomNavItem(
      icon: Icons.folder_outlined,
      selectedIcon: Icons.folder_rounded,
      label: 'Files',
    ),
    NexaBottomNavItem(
      icon: Icons.people_outline_rounded,
      selectedIcon: Icons.people_rounded,
      label: 'Shared',
    ),
    NexaBottomNavItem(
      icon: Icons.photo_library_outlined,
      selectedIcon: Icons.photo_library_rounded,
      label: 'Photos',
    ),
    NexaBottomNavItem(
      icon: Icons.more_horiz_rounded,
      selectedIcon: Icons.more_horiz_rounded,
      label: 'More',
    ),
  ];
}
