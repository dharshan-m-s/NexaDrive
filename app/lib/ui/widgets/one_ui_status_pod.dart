import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_motion.dart';
import '../../core/design/app_typography.dart';
import '../../core/design/app_gradients.dart';

/// One UI status pod — the "at a glance" Now Bar-inspired surface.
///
/// A compact, reachable floating pod that keeps long-running work visible
/// without owning the screen: avatar/icon tile, a two-line description,
/// an optional thin progress line, and a trailing hint. Tapping the pod
/// navigates to the durable surface (e.g. Transfers).
class OneUiStatusPod extends StatelessWidget {
  final IconData icon;
  final Color? tint;
  final String title;
  final String? subtitle;
  final double? progress; // 0..1 when the work is quantifiable
  final String? trailing;
  final VoidCallback? onTap;
  final GradientFamily? gradient;

  const OneUiStatusPod({
    super.key,
    required this.icon,
    this.tint,
    required this.title,
    this.subtitle,
    this.progress,
    this.trailing,
    this.onTap,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final color = tint ?? AppColors.accentFor(brightness);

    final iconTile = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: gradient != null
            ? null
            : AppColors.accentSubtleFor(brightness),
        gradient: gradient != null
            ? AppGradients.soft(gradient!, brightness)
            : null,
        borderRadius: BorderRadius.circular(AppDimens.radiusInner),
      ),
      child: Icon(icon, color: color, size: AppDimens.iconMedium),
    );

    return Semantics(
      button: true,
      label: '$title${subtitle == null ? '' : ', $subtitle'}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.space16,
            vertical: AppDimens.space12,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppDimens.radiusCard),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadowColorSoft,
                blurRadius: 12,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              iconTile,
              const SizedBox(width: AppDimens.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.rowTitle.copyWith(
                        color: AppColors.textPrimaryFor(brightness),
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
                    if (progress != null) ...[
                      const SizedBox(height: AppDimens.space8),
                      TweenAnimationBuilder<double>(
                        tween: Tween(
                          begin: 0,
                          end: progress!.clamp(0.0, 1.0),
                        ),
                        duration: AppMotion.resolve(context, AppMotion.normal),
                        curve: AppMotion.standard,
                        builder: (context, value, _) => ClipRRect(
                          borderRadius:
                              BorderRadius.circular(AppDimens.radiusPill),
                          child: LinearProgressIndicator(
                            value: value,
                            minHeight: 4,
                            color: color,
                            backgroundColor:
                                Theme.of(context).colorScheme.surfaceContainer,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppDimens.space12),
                Text(
                  trailing!,
                  style: AppTextStyle.micro.copyWith(
                    color: AppColors.textTertiaryFor(brightness),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}