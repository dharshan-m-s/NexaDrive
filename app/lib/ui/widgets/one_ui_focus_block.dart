import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';

/// How a focus block lays out.
enum OneUiFocusBlockLayout { vertical, horizontal }

/// One UI "focus block" — the signature interaction block.
///
/// Samsung's focus block: a comfortably-sized rounded surface holding a
/// soft icon tile + a label, tappable immediately, living in the interaction
/// area. Vertical blocks are Home quick actions; horizontal blocks are rows
/// inside sheets/lists.
class OneUiFocusBlock extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? tint;
  final VoidCallback? onTap;
  final OneUiFocusBlockLayout layout;
  final bool showChevron;
  final bool enabled;
  final Widget? trailing;
  final Key? actionKey;

  const OneUiFocusBlock({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.tint,
    this.onTap,
    this.layout = OneUiFocusBlockLayout.horizontal,
    this.showChevron = false,
    this.enabled = true,
    this.trailing,
    this.actionKey,
  });

  @override
  Widget build(BuildContext context) {
    if (layout == OneUiFocusBlockLayout.vertical) {
      return _vertical(context);
    }
    return _horizontal(context);
  }

  Widget _iconTile(BuildContext context, {bool large = false}) {
    final brightness = Theme.of(context).brightness;
    final color = tint ?? AppColors.accentFor(brightness);
    final subtle = AppColors.accentSubtleFor(brightness);
    final size = large ? 56.0 : AppDimens.iconTileLarge;
    final radius = large ? AppDimens.radiusInner : AppDimens.radiusTile;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: subtle,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(icon, color: color, size: AppDimens.iconMedium),
    );
  }

  Widget _vertical(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final color = AppColors.textPrimaryFor(brightness);
    return Semantics(
      button: true,
      enabled: enabled,
      child: InkWell(
        key: actionKey,
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.space12,
            vertical: AppDimens.space16,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppDimens.radiusCard),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _iconTile(context, large: true),
              const SizedBox(height: AppDimens.space10),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTextStyle.chipLabel.copyWith(
                  color: enabled ? color : AppColors.textTertiaryFor(brightness),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _horizontal(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final color = AppColors.textPrimaryFor(brightness);
    return Semantics(
      button: true,
      enabled: enabled,
      child: InkWell(
        key: actionKey,
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppDimens.radiusTile),
        child: Container(
          constraints: const BoxConstraints(minHeight: AppDimens.listHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppDimens.space12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppDimens.radiusTile),
          ),
          child: Row(
            children: [
              _iconTile(context),
              const SizedBox(width: AppDimens.space16),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.rowTitle.copyWith(
                        color: enabled ? color : AppColors.textTertiaryFor(brightness),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppDimens.space2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.caption.copyWith(
                          color: AppColors.textSecondaryFor(brightness),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null)
                trailing!
              else if (showChevron)
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textTertiaryFor(brightness),
                  size: AppDimens.iconMedium,
                ),
            ],
          ),
        ),
      ),
    );
  }
}