import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';
import '../../core/design/app_motion.dart';

/// Linear progress indicator with label.
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
    this.height = 4,
    this.showPercentage = true,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final accent = color ?? AppColors.accentFor(brightness);
    final bg = backgroundColor ?? accent.withValues(alpha: 0.12);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null || (showPercentage && value != null)) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (label != null)
                Text(
                  label!,
                  style: AppTextStyle.caption1.copyWith(
                    color: AppColors.labelSecondaryFor(brightness),
                  ),
                ),
              if (showPercentage && value != null)
                Text(
                  '${(value! * 100).round()}%',
                  style: AppTextStyle.caption2.copyWith(
                    color: AppColors.labelPrimaryFor(brightness),
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppDimens.space6),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(height / 2),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: (value ?? 0).clamp(0.0, 1.0)),
            duration: AppMotion.resolve(context, AppMotion.normal),
            curve: AppMotion.standardCurve,
            builder: (context, v, _) => LinearProgressIndicator(
              value: value != null ? v : null,
              minHeight: height,
              color: accent,
              backgroundColor: bg,
            ),
          ),
        ),
        if (valueLabel != null) ...[
          const SizedBox(height: AppDimens.space6),
          Text(
            valueLabel!,
            style: AppTextStyle.caption2.copyWith(
              color: AppColors.labelTertiaryFor(brightness),
            ),
          ),
        ],
      ],
    );
  }
}

/// Circular progress indicator.
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
    final brightness = Theme.of(context).brightness;
    final accent = color ?? AppColors.accentFor(brightness);
    final bg = backgroundColor ?? accent.withValues(alpha: 0.12);

    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        value: value,
        strokeWidth: strokeWidth,
        strokeCap: StrokeCap.round,
        color: accent,
        backgroundColor: bg,
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
    final brightness = Theme.of(context).brightness;
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        strokeCap: StrokeCap.round,
        color: color ?? AppColors.accentFor(brightness),
      ),
    );
  }
}
