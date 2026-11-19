import 'package:flutter/material.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_motion.dart';
import '../../../core/design/app_typography.dart';

/// Desktop navigation — a Material 3 persistent rail.
///
/// Primary destinations use a `secondaryContainer` selected indicator and
/// Material state layers; utility actions sit in a quieter group below.
class SideNavigation extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelected;
  final VoidCallback onSync;
  final VoidCallback onTransfers;
  final VoidCallback onNotifications;

  const SideNavigation({
    super.key,
    required this.index,
    required this.onSelected,
    required this.onSync,
    required this.onTransfers,
    required this.onNotifications,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: AppDimens.navRailWidth,
      child: Container(
        color: scheme.surfaceContainerLow,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.space20,
                AppDimens.space24,
                AppDimens.space20,
                AppDimens.space20,
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius:
                          BorderRadius.circular(AppDimens.radiusMedium),
                    ),
                    child: Icon(
                      Icons.cloud_rounded,
                      color: scheme.onPrimaryContainer,
                      size: AppDimens.iconMedium,
                    ),
                  ),
                  const SizedBox(width: AppDimens.space12),
                  Expanded(
                    child: Text(
                      'NexaDrive',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.titleMedium.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.space12,
                ),
                children: [
                  SideNavItem(
                    icon: Icons.home_outlined,
                    selectedIcon: Icons.home_rounded,
                    label: 'Home',
                    selected: index == 0,
                    onTap: () => onSelected(0),
                  ),
                  SideNavItem(
                    icon: Icons.folder_outlined,
                    selectedIcon: Icons.folder_rounded,
                    label: 'My files',
                    selected: index == 1,
                    onTap: () => onSelected(1),
                  ),
                  SideNavItem(
                    icon: Icons.people_outline_rounded,
                    selectedIcon: Icons.people_rounded,
                    label: 'Shared',
                    selected: index == 2,
                    onTap: () => onSelected(2),
                  ),
                  SideNavItem(
                    icon: Icons.photo_library_outlined,
                    selectedIcon: Icons.photo_library_rounded,
                    label: 'Photos',
                    selected: index == 3,
                    onTap: () => onSelected(3),
                  ),
                  SideNavItem(
                    icon: Icons.delete_outline_rounded,
                    selectedIcon: Icons.delete_rounded,
                    label: 'Trash',
                    selected: index == 4,
                    onTap: () => onSelected(4),
                  ),
                  const SizedBox(height: AppDimens.space12),
                  _UtilityNavItem(
                    icon: Icons.cloud_upload_outlined,
                    label: 'Transfers',
                    onTap: onTransfers,
                  ),
                  _UtilityNavItem(
                    icon: Icons.sync_rounded,
                    label: 'Sync center',
                    onTap: onSync,
                  ),
                  _UtilityNavItem(
                    icon: Icons.notifications_outlined,
                    label: 'Notifications',
                    onTap: onNotifications,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.space12,
                AppDimens.space8,
                AppDimens.space12,
                AppDimens.space16,
              ),
              child: SideNavItem(
                icon: Icons.settings_outlined,
                selectedIcon: Icons.settings_rounded,
                label: 'Settings',
                selected: index == 5,
                onTap: () => onSelected(5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single rail row with a Material 3 selected indicator.
class SideNavItem extends StatelessWidget {
  final IconData icon;
  final IconData? selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const SideNavItem({
    super.key,
    required this.icon,
    this.selectedIcon,
    required this.label,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = scheme.onSecondaryContainer;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.space2),
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        surfaceTintColor: Colors.transparent,
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
          child: AnimatedContainer(
            duration: AppMotion.resolve(context, AppMotion.fast),
            height: AppDimens.touchTarget,
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.space16,
            ),
            child: Row(
              children: [
                Icon(
                  selected ? (selectedIcon ?? icon) : icon,
                  size: AppDimens.iconMedium,
                  color: selected ? active : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppDimens.space12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.labelLarge.copyWith(
                      color: selected ? active : scheme.onSurface,
                    ),
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

class _UtilityNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _UtilityNavItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.space2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
          child: SizedBox(
            height: AppDimens.touchTarget,
            child: Row(
              children: [
                const SizedBox(width: AppDimens.space16),
                Icon(
                  icon,
                  size: AppDimens.iconMedium,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppDimens.space12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.labelLarge.copyWith(
                      color: scheme.onSurface,
                    ),
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
