import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_motion.dart';
import '../../core/design/app_typography.dart';

/// Floating iOS-style bottom navigation pill.
///
/// A capsule inset from the screen edges that floats over the page with a
/// translucent glass fill, a hairline edge, and a soft shadow that lifts it
/// off the content — the iOS Liquid Glass tab bar, without a full-width
/// docked strip.
///
/// The selected destination is marked by an accent capsule that slides between
/// tabs. Honours reduced motion and keeps every destination on the 48pt touch
/// target.
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

    // The pill's glass appearance is provided by the parent BackdropFilter
    // in app_shell.dart. Here we only clip to the pill radius and paint
    // a restrained translucent fill so icons and labels remain readable.
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppDimens.radiusPill),
      child: Container(
        height: AppDimens.bottomNavHeight,
        // Restrained translucent fill — the glass blur comes from the parent
        // BackdropFilter. The low alpha ensures the page behind remains
        // visible while keeping ink legible.
        color: AppColors.surfaceFor(brightness).withValues(alpha: 0.3),
        child: _NavRow(
          items: items,
          currentIndex: currentIndex,
          onTap: onTap,
          brightness: brightness,
        ),
      ),
    );
  }
}

/// Row of navigation destinations with a sliding selection capsule.
class _NavRow extends StatelessWidget {
  final List<NexaBottomNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final Brightness brightness;

  const _NavRow({
    required this.items,
    required this.currentIndex,
    required this.onTap,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context) {
    final count = items.length;
    final selectionColor = AppColors.accentContainerFor(brightness);
    const capsuleInset = 12.0;
    const capsuleHeight = 40.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth / count;
        final capsuleWidth =
            (itemWidth - capsuleInset * 2).clamp(0.0, itemWidth);
        final showCapsule = currentIndex >= 0 && currentIndex < count;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Selection capsule that slides between destinations.
            if (showCapsule)
              AnimatedPositioned(
                duration: AppMotion.resolve(context, AppMotion.fast),
                curve: AppMotion.resolveCurve(context, AppMotion.standardCurve),
                left: currentIndex * itemWidth + capsuleInset,
                top: (AppDimens.bottomNavHeight - capsuleHeight) / 2,
                width: capsuleWidth,
                height: capsuleHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: selectionColor,
                    borderRadius: BorderRadius.circular(AppDimens.radiusInner),
                  ),
                ),
              ),
            // Destination taps.
            Row(
              children: List.generate(count, (index) {
                return Expanded(
                  child: _NavItem(
                    item: items[index],
                    isSelected: index == currentIndex,
                    onTap: () => onTap(index),
                    brightness: brightness,
                  ),
                );
              }),
            ),
          ],
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
    final activeColor = AppColors.accentFor(brightness);
    final inactiveColor = AppColors.textSecondaryFor(brightness);

    // Icon: selected is full-colour; unselected is secondary-label grey so the
    // active tab reads first.
    final iconColor = isSelected ? activeColor : inactiveColor;
    final icon = isSelected ? item.selectedIcon : item.icon;

    // Label: selected is the accent-coloured primary ink; unselected is quiet
    // secondary text.
    final labelColor = isSelected ? activeColor : inactiveColor;
    final labelWeight = isSelected ? FontWeight.w600 : FontWeight.w500;

    return Semantics(
      button: true,
      selected: isSelected,
      label: item.label,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppDimens.space6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // The glyph cross-fades between its outlined and filled forms
                // with a gentle scale, so selection reads as a settle rather
                // than a hard swap.
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
                    icon,
                    key: ValueKey<bool>(isSelected),
                    size: AppDimens.iconMedium,
                    color: iconColor,
                  ),
                ),
                const SizedBox(height: AppDimens.space2),
                AnimatedDefaultTextStyle(
                  duration: AppMotion.resolve(context, AppMotion.fast),
                  curve: AppMotion.curveFor(context, AppMotion.standardCurve),
                  style: AppTextStyle.navLabel.copyWith(
                    color: labelColor,
                    fontWeight: labelWeight,
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
