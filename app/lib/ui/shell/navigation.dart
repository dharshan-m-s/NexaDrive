import 'package:flutter/material.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';

/// Desktop navigation rail — One UI sidebar with brand at top, primary
/// destinations, and utility destinations pinned at the bottom.
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
    final brightness = Theme.of(context).brightness;
    final surface =
        brightness == Brightness.dark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final primary = AppColors.textPrimaryFor(brightness);
    final accent = AppColors.accentFor(brightness);

    return SizedBox(
      width: 236,
      child: Material(
        color: surface,
        child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.space20, AppDimens.space24, AppDimens.space20, AppDimens.space20,
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(AppDimens.radiusInner),
                  ),
                  child: Icon(Icons.cloud_rounded, color: surface, size: 22),
                ),
                const SizedBox(width: AppDimens.space12),
                Expanded(
                  child: Text(
                    'NexaDrive',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.sectionHeader.copyWith(color: primary),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: AppDimens.space12),
              children: [
                SideNavItem(icon: Icons.home_outlined, selectedIcon: Icons.home_rounded, label: 'Home', selected: index == 0, onTap: () => onSelected(0)),
                SideNavItem(icon: Icons.folder_outlined, selectedIcon: Icons.folder_rounded, label: 'My files', selected: index == 1, onTap: () => onSelected(1)),
                SideNavItem(icon: Icons.people_outline_rounded, selectedIcon: Icons.people_rounded, label: 'Shared', selected: index == 2, onTap: () => onSelected(2)),
                SideNavItem(icon: Icons.photo_library_outlined, selectedIcon: Icons.photo_library_rounded, label: 'Photos', selected: index == 3, onTap: () => onSelected(3)),
                SideNavItem(icon: Icons.delete_outline_rounded, selectedIcon: Icons.delete_rounded, label: 'Trash', selected: index == 4, onTap: () => onSelected(4)),
                const SizedBox(height: AppDimens.space12),
                _UtilityNavItem(
                  icon: Icons.cloud_upload_outlined,
                  label: 'Transfers',
                  onTap: onTransfers,
                ),
                _UtilityNavItem(icon: Icons.sync_rounded, label: 'Sync center', onTap: onSync),
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
              AppDimens.space12, AppDimens.space8, AppDimens.space12, AppDimens.space16,
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

/// A single rail row.
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
    final brightness = Theme.of(context).brightness;
    final onAccent = AppColors.onAccentContainerFor(brightness);
    final color = AppColors.textPrimaryFor(brightness);

    return ListTile(
      onTap: onTap,
      selected: selected,
      selectedTileColor: AppColors.accentContainerFor(brightness),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusTile),
      ),
      leading: Icon(
        selected ? (selectedIcon ?? icon) : icon,
        size: AppDimens.iconMedium,
        color: selected
            ? onAccent
            : AppColors.textSecondaryFor(brightness),
      ),
      title: Text(
        label,
        style: AppTextStyle.rowTitle.copyWith(
          color: selected ? onAccent : color,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      minLeadingWidth: 28,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppDimens.space12),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _UtilityNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _UtilityNavItem({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusTile),
      ),
      leading: Icon(
        icon,
        size: AppDimens.iconMedium,
        color: AppColors.textSecondaryFor(brightness),
      ),
      title: Text(
        label,
        style: AppTextStyle.rowTitle.copyWith(
          color: AppColors.textPrimaryFor(brightness),
          fontWeight: FontWeight.w500,
        ),
      ),
      minLeadingWidth: 28,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppDimens.space12),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Mobile bottom navigation — One UI style: clean pill labels, restrained
/// accent indicator, five destinations with the fifth opening a More sheet.
///
/// Built on the Material [NavigationBar] so system/theme navigation behavior
/// stays consistent; the app's navigation-bar theme supplies One UI styling.
class OneUiBottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelected;

  const OneUiBottomNav({super.key, required this.index, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: index,
      onDestinationSelected: onSelected,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: List.generate(_labels.length, (i) {
        return NavigationDestination(
          icon: Icon(_icons[i]),
          selectedIcon: Icon(_selectedIcons[i]),
          label: _labels[i],
        );
      }),
    );
  }

  static const _labels = ['Home', 'Files', 'Shared', 'Photos', 'More'];
  static const _icons = [
    Icons.home_outlined,
    Icons.folder_outlined,
    Icons.people_outline_rounded,
    Icons.photo_library_outlined,
    Icons.more_horiz_rounded,
  ];
  static const _selectedIcons = [
    Icons.home_rounded,
    Icons.folder_rounded,
    Icons.people_rounded,
    Icons.photo_library_rounded,
    Icons.more_horiz_rounded,
  ];
}