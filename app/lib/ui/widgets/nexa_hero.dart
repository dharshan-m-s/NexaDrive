import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';
import '../../core/design/app_motion.dart';
import 'nexa_surface.dart';

/// iOS-style hero card with large metric and progress ring.
class NexaHero extends StatelessWidget {
  final String label;
  final String value;
  final String? secondary;
  final String detail;
  final double fraction; // 0..1
  final VoidCallback? onTap;
  final Widget? trailing;

  const NexaHero({
    super.key,
    required this.label,
    required this.value,
    required this.detail,
    required this.fraction,
    this.secondary,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final onGradient = AppColors.heroTextOnGradient(brightness);

    return NexaSurface(
      level: NexaSurfaceLevel.floating,
      radius: AppDimens.radiusXLarge,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(
        AppDimens.space20,
        AppDimens.space20,
        AppDimens.space20,
        AppDimens.space16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label.toUpperCase(),
                      style: AppTextStyle.caption2.copyWith(
                        color: onGradient.withValues(alpha: 0.72),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        // Subtle gradient-aware tint for light mode
                      ),
                    ),
                    const SizedBox(height: AppDimens.space4),
                    Text(
                      value,
                      style: AppTextStyle.heroTitle.copyWith(
                        color: onGradient,
                        height: 1.05,
                      ),
                    ),
                    if (secondary != null && secondary!.isNotEmpty) ...[
                      const SizedBox(height: AppDimens.space2),
                      Text(
                        secondary!,
                        style: AppTextStyle.metricValue.copyWith(
                          color: onGradient.withValues(alpha: 0.92),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppDimens.space16),
              if (trailing != null)
                trailing!
              else
                _HeroRing(
                  fraction: fraction,
                  size: 88,
                  stroke: 6,
                  color: onGradient,
                  track: onGradient.withValues(alpha: 0.22),
                ),
            ],
          ),
          const SizedBox(height: AppDimens.space16),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppDimens.radiusPill),
            child: TweenAnimationBuilder<double>(
              tween: Tween(
                begin: 0,
                end: fraction.clamp(0.0, 1.0),
              ),
              duration: AppMotion.resolve(context, AppMotion.normal),
              curve: AppMotion.standardCurve,
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                color: AppColors.surfaceFor(brightness),
                backgroundColor: onGradient.withValues(alpha: 0.25),
              ),
            ),
          ),
          const SizedBox(height: AppDimens.space10),
          Text(
            detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.caption1.copyWith(
              color: onGradient.withValues(alpha: 0.90),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroRing extends StatelessWidget {
  final double fraction;
  final double size;
  final double stroke;
  final Color color;
  final Color track;

  const _HeroRing({
    required this.fraction,
    required this.size,
    required this.stroke,
    required this.color,
    required this.track,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: 1,
            strokeWidth: stroke,
            strokeCap: StrokeCap.round,
            color: track,
            backgroundColor: Colors.transparent,
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(
              begin: 0,
              end: fraction.clamp(0.0, 1.0),
            ),
            duration: AppMotion.resolve(context, AppMotion.normal),
            curve: AppMotion.standardCurve,
            builder: (context, v, _) => CircularProgressIndicator(
              value: v,
              strokeWidth: stroke,
              strokeCap: StrokeCap.round,
              color: color,
              backgroundColor: Colors.transparent,
            ),
          ),
        ],
      ),
    );
  }
}
