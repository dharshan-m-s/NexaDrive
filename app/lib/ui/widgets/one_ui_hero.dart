import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_gradients.dart';
import '../../core/design/app_motion.dart';
import '../../core/design/app_typography.dart';

/// One UI storage hero — the signature Home surface.
///
/// A calm cloud→ocean hero that answers the two questions people actually
/// care about: how much have I used, and how much do I have left. Reads in
/// the viewing area (large metric + ring, highly readable text), responds in
/// the interaction area (whole card is tappable).
class OneUiHero extends StatelessWidget {
  final String label;
  final String value;
  final String? secondary;
  final String detail;
  final double fraction; // 0..1
  final VoidCallback? onTap;
  final LinearGradient? gradient;

  const OneUiHero({
    super.key,
    required this.label,
    required this.value,
    required this.detail,
    required this.fraction,
    this.secondary,
    this.onTap,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final scheme = Theme.of(context).colorScheme;
    final onGradient = AppColors.heroTextOnGradient(brightness);
    final g = gradient ?? AppGradients.storageHero(brightness);

    return Semantics(
      button: onTap != null,
      label: '$label $value. $detail',
      child: Material(
        color: Colors.transparent,
        child: Ink(
        decoration: BoxDecoration(
          gradient: g,
          borderRadius: BorderRadius.circular(AppDimens.radiusHero),
        ),
        child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppDimens.radiusHero),
            child: Container(
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
                              style: AppTextStyle.micro.copyWith(
                                color: onGradient.withValues(alpha: 0.72),
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.1,
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
                      curve: AppMotion.standard,
                      builder: (context, v, _) => LinearProgressIndicator(
                        value: v,
                        minHeight: 6,
                        color: scheme.surface,
                        backgroundColor: onGradient.withValues(alpha: 0.25),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppDimens.space10),
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.caption.copyWith(
                      color: onGradient.withValues(alpha: 0.90),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
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
            curve: AppMotion.standard,
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