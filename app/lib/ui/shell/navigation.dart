import 'package:flutter/material.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_motion.dart';
import '../../../core/design/app_typography.dart';

/// Desktop navigation — an iOS-style source list: brand at top, the primary
/// destinations, then utility destinations, with the active row marked by an
/// inset group fill rather than a rail indicator.
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
    final surface = AppColors.surfaceFor(brightness);
    final primary = AppColors.textPrimaryFor(brightness);
    final accent = AppColors.accentFor(brightness);

    return SizedBox(
      width: AppDimens.navRailWidth,
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          border: Border(
            right: BorderSide(color: AppColors.separatorFor(brightness)),
          ),
        ),
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
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(Icons.cloud_rounded,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: AppDimens.space12),
                  Expanded(
                    child: Text(
                      'NexaDrive',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          AppTextStyle.sectionHeader.copyWith(color: primary),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppDimens.space12),
                children: [
                  SideNavItem(
                      icon: Icons.home_outlined,
                      selectedIcon: Icons.home_rounded,
                      label: 'Home',
                      selected: index == 0,
                      onTap: () => onSelected(0)),
                  SideNavItem(
                      icon: Icons.folder_outlined,
                      selectedIcon: Icons.folder_rounded,
                      label: 'My files',
                      selected: index == 1,
                      onTap: () => onSelected(1)),
                  SideNavItem(
                      icon: Icons.people_outline_rounded,
                      selectedIcon: Icons.people_rounded,
                      label: 'Shared',
                      selected: index == 2,
                      onTap: () => onSelected(2)),
                  SideNavItem(
                      icon: Icons.photo_library_outlined,
                      selectedIcon: Icons.photo_library_rounded,
                      label: 'Photos',
                      selected: index == 3,
                      onTap: () => onSelected(3)),
                  SideNavItem(
                      icon: Icons.delete_outline_rounded,
                      selectedIcon: Icons.delete_rounded,
                      label: 'Trash',
                      selected: index == 4,
                      onTap: () => onSelected(4)),
                  const SizedBox(height: AppDimens.space12),
                  _UtilityNavItem(
                    icon: Icons.cloud_upload_outlined,
                    label: 'Transfers',
                    onTap: onTransfers,
                  ),
                  _UtilityNavItem(
                      icon: Icons.sync_rounded,
                      label: 'Sync center',
                      onTap: onSync),
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

/// A single sidebar row: an inset rounded selection fill, accent glyph.
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
    final accent = AppColors.accentFor(brightness);
    final secondary = AppColors.textSecondaryFor(brightness);
    final primary = AppColors.textPrimaryFor(brightness);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.space1),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppDimens.radiusSmall),
          child: AnimatedContainer(
            duration: AppMotion.resolve(context, AppMotion.fast),
            height: AppDimens.listHeightNarrow,
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.space12,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.accentContainerFor(brightness)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppDimens.radiusSmall),
            ),
            child: Row(
              children: [
                Icon(
                  selected ? (selectedIcon ?? icon) : icon,
                  size: 20,
                  color: selected ? accent : secondary,
                ),
                const SizedBox(width: AppDimens.space12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.bodyEmphasized.copyWith(
                      fontSize: 15,
                      color: selected ? accent : primary,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
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

  const _UtilityNavItem(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final secondary = AppColors.textSecondaryFor(brightness);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.space1),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppDimens.radiusSmall),
          child: SizedBox(
            height: AppDimens.listHeightNarrow,
            child: Row(
              children: [
                const SizedBox(width: AppDimens.space12),
                Icon(icon, size: 20, color: secondary),
                const SizedBox(width: AppDimens.space12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.body.copyWith(
                      fontSize: 15,
                      color: AppColors.textPrimaryFor(brightness),
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
