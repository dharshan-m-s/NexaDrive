import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';
import 'nexa_surface.dart';

/// iOS-style status pod (compact status card).
class NexaStatusPod extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String title;
  final String subtitle;
  final String? trailing;
  final VoidCallback? onTap;

  const NexaStatusPod({
    super.key,
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return NexaSurface(
      level: NexaSurfaceLevel.grouped,
      radius: AppDimens.radiusMedium,
      padding: const EdgeInsets.all(AppDimens.space16),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppDimens.radiusMedium),
            ),
            child: Icon(icon, size: 22, color: tint),
          ),
          const SizedBox(width: AppDimens.space16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyle.title2.copyWith(
                    color: AppColors.labelPrimaryFor(brightness),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: AppDimens.space2),
                Text(
                  subtitle,
                  style: AppTextStyle.caption1.copyWith(
                    color: AppColors.labelSecondaryFor(brightness),
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppDimens.space12),
            Text(
              trailing!,
              style: AppTextStyle.caption1.copyWith(
                color: AppColors.labelSecondaryFor(brightness),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (onTap != null) ...[
            const SizedBox(width: AppDimens.space8),
            Icon(
              Icons.chevron_right_rounded,
              size: AppDimens.iconMedium,
              color: AppColors.labelTertiaryFor(brightness),
            ),
          ],
        ],
      ),
    );
  }
}
