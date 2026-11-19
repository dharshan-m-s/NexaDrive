import 'package:flutter/material.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';
import 'nexa_surface.dart';

/// Material 3 quick-action block on a tonal grouped surface.
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
    final scheme = Theme.of(context).colorScheme;
    final accent = tint ?? scheme.primary;
    final horizontal = layout == NexaFocusBlockLayout.horizontal;

    final content = Column(
      crossAxisAlignment:
          horizontal ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width:
              horizontal ? AppDimens.iconTileLarge : AppDimens.touchTargetLarge,
          height:
              horizontal ? AppDimens.iconTileLarge : AppDimens.touchTargetLarge,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(AppDimens.radiusMedium),
          ),
          child: Icon(
            icon,
            size: horizontal ? AppDimens.iconSmall : AppDimens.iconMedium,
            color: accent,
          ),
        ),
        const SizedBox(height: AppDimens.space12),
        Text(
          title,
          textAlign: horizontal ? TextAlign.start : TextAlign.center,
          style: AppTextStyle.titleMedium.copyWith(color: scheme.onSurface),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: AppDimens.space4),
          Text(
            subtitle!,
            textAlign: horizontal ? TextAlign.start : TextAlign.center,
            style: AppTextStyle.bodySmall.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        if (showChevron && horizontal) ...[
          const SizedBox(height: AppDimens.space8),
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Text(
                'Open',
                style: AppTextStyle.labelMedium.copyWith(color: scheme.primary),
              ),
              const SizedBox(width: AppDimens.space4),
              Icon(
                Icons.chevron_right_rounded,
                size: AppDimens.iconSmall,
                color: scheme.primary,
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
      child: horizontal
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
