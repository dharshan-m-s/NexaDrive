import 'package:flutter/material.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';
import '../../core/design/app_motion.dart';

/// Material 3 linear progress indicator with labels.
class NexaProgressIndicator extends StatelessWidget {
  final double? value;
  final String? label;
  final String? valueLabel;
  final Color? color;
  final Color? backgroundColor;
  final double height;
  final bool showPercentage;

  const NexaProgressIndicator({
    super.key,
    this.value,
    this.label,
    this.valueLabel,
    this.color,
    this.backgroundColor,
    this.height = 6,
    this.showPercentage = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = color ?? scheme.primary;
    final track = backgroundColor ?? scheme.primaryContainer;
    final percentage = value == null ? null : '${(value! * 100).round()}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null || (showPercentage && percentage != null)) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (label != null)
                Text(
                  label!,
                  style: AppTextStyle.bodySmall.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              if (showPercentage && percentage != null)
                Text(
                  percentage,
                  style: AppTextStyle.labelMedium.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppDimens.space6),
        ],
        Semantics(
          label: label ?? 'Progress',
          value: valueLabel ?? percentage,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppDimens.radiusPill),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: (value ?? 0).clamp(0.0, 1.0)),
              duration: AppMotion.resolve(context, AppMotion.normal),
              curve: AppMotion.standardCurve,
              builder: (context, v, _) => LinearProgressIndicator(
                value: value != null ? v : null,
                minHeight: height,
                color: accent,
                backgroundColor: track,
              ),
            ),
          ),
        ),
        if (valueLabel != null) ...[
          const SizedBox(height: AppDimens.space6),
          Text(
            valueLabel!,
            style: AppTextStyle.bodySmall.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// Material 3 circular progress indicator.
class NexaCircularProgress extends StatelessWidget {
  final double? value;
  final double size;
  final double strokeWidth;
  final Color? color;
  final Color? backgroundColor;

  const NexaCircularProgress({
    super.key,
    this.value,
    this.size = 24,
    this.strokeWidth = 2.5,
    this.color,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        value: value,
        strokeWidth: strokeWidth,
        strokeCap: StrokeCap.round,
        color: color ?? scheme.primary,
        backgroundColor: backgroundColor ?? scheme.primaryContainer,
      ),
    );
  }
}

/// Spinner for loading states.
class NexaSpinner extends StatelessWidget {
  final double size;
  final double strokeWidth;
  final Color? color;

  const NexaSpinner({
    super.key,
    this.size = 24,
    this.strokeWidth = 2.5,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      label: 'Loading',
      child: SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          strokeWidth: strokeWidth,
          strokeCap: StrokeCap.round,
          color: color ?? scheme.primary,
        ),
      ),
    );
  }
}
