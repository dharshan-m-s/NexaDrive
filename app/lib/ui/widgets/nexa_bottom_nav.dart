import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_haptics.dart';
import '../../core/design/app_motion.dart';
import '../../core/design/app_shadows.dart';
import '../../core/design/app_typography.dart';
import 'nexa_liquid_glass.dart';

/// The floating navigation pill — NexaDrive's one signature element.
///
/// It keeps its spring-driven travelling selection and floating placement, but
/// the material is now a Material 3 tonal surface: `surfaceContainerHigh`
/// chrome, a `secondaryContainer` selection pill and Material state layers.
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
    return SizedBox(
      height: AppDimens.bottomNavHeight,
      // A quiet, token-backed lift sells the pill as a floating object without
      // turning it into a heavy card. The tonal surface stays opaque.
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
          boxShadow: AppShadows.floatingPill(Theme.of(context).brightness),
        ),
        child: NexaLiquidGlass(
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
          padding: EdgeInsets.zero,
          showShadow: false,
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
        AppMotion.pillSpring,
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
    final scheme = Theme.of(context).colorScheme;
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final count = items.length;
        final itemWidth = constraints.maxWidth / count;
        const horizontalInset = 6.0;
        final indicatorHeight = AppDimens.bottomNavHeight - AppDimens.space12;
        final indicatorWidth =
            (itemWidth - horizontalInset * 2).clamp(0.0, itemWidth);

        return AnimatedBuilder(
          animation: _selection,
          builder: (context, _) {
            final selectedPosition =
                _selection.value.clamp(0.0, (count - 1).toDouble());
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
                    child: Material(
                      color: scheme.primaryContainer,
                      surfaceTintColor: Colors.transparent,
                      elevation: 0,
                      borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                      child: const SizedBox.expand(),
                    ),
                  ),
                Row(
                  children: List.generate(count, (index) {
                    return Expanded(
                      child: _NavItem(
                        item: items[index],
                        isSelected: index == widget.currentIndex,
                        onTap: () => widget.onTap(index),
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

  const _NavItem({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeColor = scheme.onPrimaryContainer;
    final inactiveColor = scheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: isSelected,
      label: item.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (!isSelected) AppHaptics.selection();
            onTap();
          },
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
          splashColor: scheme.primary.withValues(alpha: 0.16),
          highlightColor: scheme.primary.withValues(alpha: 0.10),
          hoverColor: scheme.primary.withValues(alpha: 0.08),
          child: SizedBox(
            height: AppDimens.bottomNavHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.space2,
                vertical: AppDimens.space8,
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
                      child: child,
                    ),
                    child: Icon(
                      isSelected ? item.selectedIcon : item.icon,
                      key: ValueKey<bool>(isSelected),
                      size: AppDimens.iconMedium,
                      color: isSelected ? activeColor : inactiveColor,
                    ),
                  ),
                  const SizedBox(height: AppDimens.space6),
                  AnimatedDefaultTextStyle(
                    duration: AppMotion.resolve(context, AppMotion.fast),
                    curve: AppMotion.curveFor(context, AppMotion.standard),
                    style: AppTextStyle.navLabel.copyWith(
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
