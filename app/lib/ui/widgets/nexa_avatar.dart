import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import 'nexa_badge.dart';

/// User avatar with initials fallback.
class NexaAvatar extends StatelessWidget {
  final String? name;
  final String? imageUrl;
  final double radius;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const NexaAvatar({
    super.key,
    this.name,
    this.imageUrl,
    this.radius = AppDimens.iconTile / 2,
    this.backgroundColor,
    this.foregroundColor,
  });

  const NexaAvatar.large({
    super.key,
    this.name,
    this.imageUrl,
    this.radius = AppDimens.iconHero / 2,
    this.backgroundColor,
    this.foregroundColor,
  });

  const NexaAvatar.small({
    super.key,
    this.name,
    this.imageUrl,
    this.radius = AppDimens.iconSmall,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final accent = AppColors.accentTextFor(brightness);
    final bg = backgroundColor ?? AppColors.accentContainerFor(brightness);
    final fg = foregroundColor ?? accent;
    final parts = (name ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty);
    final initials = parts
        .take(2)
        .map((part) => String.fromCharCode(part.runes.first))
        .join()
        .toUpperCase();
    final fallback = initials.isEmpty ? '?' : initials;
    final diameter = radius * 2;

    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.separatorFor(brightness),
          width: 0.8,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl != null && imageUrl!.isNotEmpty
          ? Image.network(
              imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Center(
                child: Text(
                  fallback,
                  style: TextStyle(
                    color: fg,
                    fontSize: radius * 0.7,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
          : Center(
              child: Text(
                fallback,
                style: TextStyle(
                  color: fg,
                  fontSize: radius * 0.7,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
    );
  }
}

/// Avatar with status indicator.
class NexaAvatarWithStatus extends StatelessWidget {
  final String? name;
  final String? imageUrl;
  final double radius;
  final NexaStatus status;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const NexaAvatarWithStatus({
    super.key,
    this.name,
    this.imageUrl,
    this.radius = AppDimens.iconTile / 2,
    required this.status,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final statusSize = radius * 0.4;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        NexaAvatar(
          name: name,
          imageUrl: imageUrl,
          radius: radius,
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
        ),
        Positioned(
          right: -statusSize * 0.2,
          bottom: -statusSize * 0.2,
          child: NexaStatusIndicator(status: status, size: statusSize),
        ),
      ],
    );
  }
}
