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
    final dark = brightness == Brightness.dark;
    final ink = AppColors.heroTextOnGradient(brightness);
    final accent = AppColors.accentFor(brightness);
    final radius = BorderRadius.circular(AppDimens.radiusXLarge);
    final usedFraction = fraction.clamp(0.0, 1.0).toDouble();

    return NexaSurface(
      level: NexaSurfaceLevel.floating,
      color: AppColors.surfaceElevatedFor(brightness),
      radius: AppDimens.radiusXLarge,
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: dark
                        ? const [Color(0xFF25294D), Color(0xFF173E4B)]
                        : const [Color(0xFFE8E6FF), Color(0xFFDDF1F2)],
                  ),
                ),
              ),
            ),
            Positioned(
              top: -104,
              right: -66,
              child: IgnorePointer(
                child: Container(
                  width: 244,
                  height: 244,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        accent.withValues(alpha: dark ? 0.28 : 0.17),
                        accent.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -124,
              left: 72,
              child: IgnorePointer(
                child: Container(
                  width: 238,
                  height: 238,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF51B7B8)
                            .withValues(alpha: dark ? 0.18 : 0.15),
                        const Color(0xFF51B7B8).withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
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
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(
                            alpha: dark ? 0.10 : 0.46,
                          ),
                          borderRadius: BorderRadius.circular(
                            AppDimens.radiusStandard,
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(
                              alpha: dark ? 0.12 : 0.62,
                            ),
                          ),
                        ),
                        child: Icon(
                          Icons.cloud_outlined,
                          size: 19,
                          color: ink,
                        ),
                      ),
                      const SizedBox(width: AppDimens.space10),
                      Expanded(
                        child: Text(
                          label.toUpperCase(),
                          style: AppTextStyle.caption2.copyWith(
                            color: ink.withValues(alpha: 0.76),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.15,
                          ),
                        ),
                      ),
                      if (onTap != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              actionLabel,
                              style: AppTextStyle.caption2.copyWith(
                                color: ink.withValues(alpha: 0.72),
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.65,
                              ),
                            ),
                            const SizedBox(width: AppDimens.space4),
                            Icon(
                              Icons.arrow_outward_rounded,
                              size: 15,
                              color: ink.withValues(alpha: 0.78),
                            ),
                          ],
                        )
                      else
                        Text(
                          'OVERVIEW',
                          style: AppTextStyle.caption2.copyWith(
                            color: ink.withValues(alpha: 0.72),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.9,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppDimens.space16),
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
                              style: AppTextStyle.heroTitle.copyWith(
                                color: ink,
                                fontSize: 38,
                                height: 1.02,
                                letterSpacing: -1.0,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (secondary != null && secondary!.isNotEmpty) ...[
                              const SizedBox(height: AppDimens.space6),
                              Text(
                                secondary!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyle.subheadline.copyWith(
                                  color: ink.withValues(alpha: 0.70),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
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
                          size: 82,
                          stroke: 6,
                          color: dark
                              ? const Color(0xFFC3BDFF)
                              : const Color(0xFF6658D8),
                          track: ink.withValues(alpha: 0.14),
                          centre: '${(usedFraction * 100).round()}%',
                          centreColor: ink,
                        )
                      else
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(
                              alpha: dark ? 0.09 : 0.38,
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(
                                alpha: dark ? 0.13 : 0.58,
                              ),
                            ),
                          ),
                          child: Icon(
                            Icons.cloud_done_rounded,
                            color: ink,
                            size: 34,
                          ),
                        ),
                    ],
                  ),
                  if (secondary != null) ...[
                    const SizedBox(height: AppDimens.space16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                      child: Container(
                        height: 5,
                        color: ink.withValues(alpha: 0.13),
                        alignment: Alignment.centerLeft,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: usedFraction),
                          duration: AppMotion.resolve(
                            context,
                            AppMotion.normal,
                          ),
                          curve: AppMotion.standardCurve,
                          builder: (context, progress, _) =>
                              LinearProgressIndicator(
                            value: progress,
                            minHeight: 5,
                            color: dark
                                ? const Color(0xFFC3BDFF)
                                : const Color(0xFF6658D8),
                            backgroundColor: ink.withValues(alpha: 0.13),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppDimens.space10),
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        size: 15,
                        color: ink.withValues(alpha: 0.70),
                      ),
                      const SizedBox(width: AppDimens.space6),
                      Expanded(
                        child: Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.caption1.copyWith(
                            color: ink.withValues(alpha: 0.74),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
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
