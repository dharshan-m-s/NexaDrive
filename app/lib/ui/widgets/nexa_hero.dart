import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';
import '../../core/design/app_motion.dart';
import 'nexa_surface.dart';

/// Premium storage overview card used as the main dashboard anchor.
/// It is informational when [onTap] is null and interactive only when a real
/// destination is supplied.
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
    final brightness = Theme.of(context).brightness;
    final ink = AppColors.labelPrimaryFor(brightness);
    final secondaryInk = AppColors.labelSecondaryFor(brightness);
    final accent = AppColors.accentFor(brightness);
    final usedFraction = fraction.clamp(0.0, 1.0).toDouble();

    return NexaSurface(
      level: NexaSurfaceLevel.floating,
      color: AppColors.surfaceElevatedFor(brightness),
      radius: AppDimens.radiusXLarge,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(
        AppDimens.space20,
        AppDimens.space16,
        AppDimens.space20,
        AppDimens.space16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.accentContainerFor(brightness),
                  borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
                ),
                child: Icon(Icons.cloud_outlined, size: 20, color: AppColors.accentTextFor(brightness)),
              ),
              const SizedBox(width: AppDimens.space10),
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyle.subheadline.copyWith(color: ink, fontWeight: FontWeight.w600),
                ),
              ),
              if (onTap != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(actionLabel, style: AppTextStyle.caption2.copyWith(color: accent, fontWeight: FontWeight.w700, letterSpacing: 0.45)),
                    const SizedBox(width: AppDimens.space4),
                    Icon(Icons.arrow_outward_rounded, size: 15, color: accent),
                  ],
                )
              else
                Text('OVERVIEW', style: AppTextStyle.caption2.copyWith(color: secondaryInk, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            ],
          ),
          const SizedBox(height: AppDimens.space20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.heroTitle.copyWith(color: ink, fontSize: 38, height: 1.02, letterSpacing: -1.0, fontWeight: FontWeight.w700),
                    ),
                    if (secondary != null && secondary!.isNotEmpty) ...[
                      const SizedBox(height: AppDimens.space6),
                      Text(secondary!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyle.subheadline.copyWith(color: secondaryInk, fontWeight: FontWeight.w500)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppDimens.space12),
              if (trailing != null)
                trailing!
              else if (secondary != null)
                _HeroRing(
                  fraction: usedFraction,
                  size: 76,
                  stroke: 6,
                  color: accent,
                  track: AppColors.fillFor(brightness),
                  centre: '${(usedFraction * 100).round()}%',
                  centreColor: ink,
                )
              else
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(color: AppColors.fillFor(brightness), shape: BoxShape.circle),
                  child: Icon(Icons.cloud_done_rounded, color: accent, size: 32),
                ),
            ],
          ),
          if (secondary != null) ...[
            const SizedBox(height: AppDimens.space20),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppDimens.radiusPill),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: usedFraction),
                duration: AppMotion.resolve(context, AppMotion.normal),
                curve: AppMotion.standardCurve,
                builder: (context, progress, _) => LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  color: accent,
                  backgroundColor: AppColors.fillFor(brightness),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppDimens.space12),
          Row(
            children: [
              Icon(Icons.check_circle_outline_rounded, size: 15, color: secondaryInk),
              const SizedBox(width: AppDimens.space6),
              Expanded(
                child: Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyle.caption1.copyWith(color: secondaryInk, fontWeight: FontWeight.w500)),
              ),
            ],
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
  final String centre;
  final Color centreColor;

  const _HeroRing({
    required this.fraction,
    required this.size,
    required this.stroke,
    required this.color,
    required this.track,
    required this.centre,
    required this.centreColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: 1,
              strokeWidth: stroke,
              strokeCap: StrokeCap.round,
              color: track,
              backgroundColor: Colors.transparent,
            ),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: fraction.clamp(0.0, 1.0)),
            duration: AppMotion.resolve(context, AppMotion.normal),
            curve: AppMotion.standardCurve,
            builder: (context, value, _) => SizedBox.expand(
              child: CircularProgressIndicator(
                value: value,
                strokeWidth: stroke,
                strokeCap: StrokeCap.round,
                color: color,
                backgroundColor: Colors.transparent,
              ),
            ),
          ),
          Text(
            centre,
            style: AppTextStyle.headline.copyWith(
              color: centreColor,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
        ],
      ),
    );
  }
}
