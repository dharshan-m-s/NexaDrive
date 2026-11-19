import 'package:flutter/material.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';

/// Flat editorial storage summary.
///
/// The dashboard anchor is deliberately not a card: a compact overline, the
/// metric, a segmented usage indicator and one quiet detail line do the work.
class NexaHero extends StatelessWidget {
  final String label;
  final String value;
  final String? secondary;
  final String detail;
  final double fraction;
  final VoidCallback? onTap;
  final String actionLabel;
  final Widget? trailing;

  const NexaHero({
    super.key,
    required this.label,
    required this.value,
    required this.detail,
    required this.fraction,
    this.secondary,
    this.onTap,
    this.actionLabel = 'BROWSE',
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final used = fraction.clamp(0.0, 1.0).toDouble();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.radiusSmall),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppDimens.space12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label.toUpperCase(),
                      style: AppTextStyle.sectionHeader.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (onTap != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          actionLabel.toUpperCase(),
                          style: AppTextStyle.labelSmall.copyWith(
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(width: AppDimens.space4),
                        Icon(
                          Icons.arrow_outward_rounded,
                          size: AppDimens.iconSmall,
                          color: scheme.primary,
                        ),
                      ],
                    )
                  else
                    Text(
                      'OVERVIEW',
                      style: AppTextStyle.labelSmall.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppDimens.space12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.metricValue.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                  if (secondary != null && secondary!.isNotEmpty) ...[
                    const SizedBox(width: AppDimens.space8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppDimens.space6),
                      child: Text(
                        secondary!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.subheadline.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                  if (trailing != null) ...[
                    const Spacer(),
                    trailing!,
                  ],
                ],
              ),
              if (secondary != null) ...[
                const SizedBox(height: AppDimens.space16),
                Semantics(
                  label: label,
                  value: '${(used * 100).round()}% used',
                  child: _SegmentedUsageBar(
                    fraction: used,
                    color: scheme.primary,
                    track: scheme.surfaceContainerHighest,
                  ),
                ),
              ],
              const SizedBox(height: AppDimens.space12),
              Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.bodySmall.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SegmentedUsageBar extends StatelessWidget {
  final double fraction;
  final Color color;
  final Color track;

  const _SegmentedUsageBar({
    required this.fraction,
    required this.color,
    required this.track,
  });

  @override
  Widget build(BuildContext context) {
    const segments = 14;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppDimens.radiusSmall),
      child: Row(
        children: List.generate(segments, (index) {
          final filled = (index + 1) / segments <= fraction + 0.0001;
          return Expanded(
            child: Container(
              height: AppDimens.space8,
              margin: EdgeInsets.only(
                right: index == segments - 1 ? 0 : AppDimens.space2,
              ),
              color: filled ? color : track,
            ),
          );
        }),
      ),
    );
  }
}
