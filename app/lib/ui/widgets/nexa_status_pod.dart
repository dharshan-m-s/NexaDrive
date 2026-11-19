import 'package:flutter/material.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';
import 'nexa_surface.dart';

/// Compact Material 3 status panel with a tonal icon well and semantic tint.
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
    final scheme = Theme.of(context).colorScheme;

    return NexaSurface(
      level: NexaSurfaceLevel.grouped,
      radius: AppDimens.radiusMedium,
      padding: const EdgeInsets.all(AppDimens.space16),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: AppDimens.iconTileLarge,
            height: AppDimens.iconTileLarge,
            decoration: BoxDecoration(
              color: tint.withValues(
                alpha: scheme.brightness == Brightness.dark ? 0.20 : 0.12,
              ),
              borderRadius: BorderRadius.circular(AppDimens.radiusMedium),
            ),
            child: Icon(icon, size: AppDimens.iconMedium, color: tint),
          ),
          const SizedBox(width: AppDimens.space16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyle.titleMedium.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: AppDimens.space4),
                Text(
                  subtitle,
                  style: AppTextStyle.bodySmall.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppDimens.space12),
            Text(
              trailing!,
              style: AppTextStyle.labelMedium.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (onTap != null) ...[
            const SizedBox(width: AppDimens.space8),
            Icon(
              Icons.chevron_right_rounded,
              size: AppDimens.iconMedium,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );
  }
}
