import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';
import 'nexa_surface.dart';

/// iOS-style focus block (large tappable card for quick actions).
class NexaFocusBlock extends StatelessWidget {
  final IconData icon;
  final Color? tint;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool showChevron;
  final NexaFocusBlockLayout layout;

  const NexaFocusBlock({
    super.key,
    required this.icon,
    required this.title,
    this.tint,
    this.subtitle,
    this.onTap,
    this.showChevron = false,
    this.layout = NexaFocusBlockLayout.vertical,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final accent = tint ?? AppColors.accentFor(brightness);

    final content = Column(
      crossAxisAlignment: layout == NexaFocusBlockLayout.horizontal
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: layout == NexaFocusBlockLayout.horizontal ? 48 : 56,
          height: layout == NexaFocusBlockLayout.horizontal ? 48 : 56,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(AppDimens.radiusMedium),
          ),
          child: Icon(
            icon,
            size: layout == NexaFocusBlockLayout.horizontal ? 22 : 26,
            color: accent,
          ),
        ),
        const SizedBox(height: AppDimens.space12),
        Text(
          title,
          textAlign: layout == NexaFocusBlockLayout.horizontal
              ? TextAlign.start
              : TextAlign.center,
          style: AppTextStyle.title2.copyWith(
            color: AppColors.labelPrimaryFor(brightness),
            fontWeight: FontWeight.w500,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: AppDimens.space4),
          Text(
            subtitle!,
            textAlign: layout == NexaFocusBlockLayout.horizontal
                ? TextAlign.start
                : TextAlign.center,
            style: AppTextStyle.caption1.copyWith(
              color: AppColors.labelSecondaryFor(brightness),
            ),
          ),
        ],
        if (showChevron && layout == NexaFocusBlockLayout.horizontal) ...[
          const SizedBox(height: AppDimens.space8),
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Text(
                'Open',
                style: AppTextStyle.caption1.copyWith(
                  color: AppColors.accentFor(brightness),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: AppDimens.space4),
              Icon(
                Icons.chevron_right_rounded,
                size: AppDimens.iconSmall,
                color: AppColors.accentFor(brightness),
              ),
            ],
          ),
        ],
      ],
    );

    return NexaSurface(
      level: NexaSurfaceLevel.grouped,
      radius: AppDimens.radiusMedium,
      padding: const EdgeInsets.all(AppDimens.space16),
      onTap: onTap,
      child: layout == NexaFocusBlockLayout.horizontal
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                content,
                if (showChevron) const Spacer(),
              ],
            )
          : content,
    );
  }
}

enum NexaFocusBlockLayout { vertical, horizontal }
