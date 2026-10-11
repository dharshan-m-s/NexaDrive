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
    final accent = AppColors.accentFor(brightness);
    final bg = backgroundColor ?? accent.withValues(alpha: 0.14);

    String initial = '?';
    if (name != null && name!.trim().isNotEmpty) {
      initial = name!.trim().runes.first.toString().toUpperCase();
    }

    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: bg,
        backgroundImage: NetworkImage(imageUrl!),
        onBackgroundImageError: (_, __) => {},
        child: imageUrl == null ? Text(initial, style: _textStyle) : null,
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      child: Text(
        initial,
        style: _textStyle,
      ),
    );
  }

  TextStyle get _textStyle => TextStyle(
        color: foregroundColor ??
            AppColors.accentFor(
              WidgetsBinding.instance.platformDispatcher.platformBrightness,
            ),
        fontSize: radius * 0.7,
        fontWeight: FontWeight.w600,
      );
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
