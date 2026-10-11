import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';

/// Small status badge (dot, count, label).
class NexaBadge extends StatelessWidget {
  final String? label;
  final int? count;
  final Color? color;
  final Color? backgroundColor;
  final bool isDot;
  final double size;

  const NexaBadge({
    super.key,
    this.label,
    this.count,
    this.color,
    this.backgroundColor,
    this.isDot = false,
    this.size = 16,
  });

  /// Simple colored dot.
  const NexaBadge.dot({
    super.key,
    required this.color,
    this.size = 8,
  })  : label = null,
        count = null,
        backgroundColor = null,
        isDot = true;

  /// Numeric count badge.
  const NexaBadge.count({
    super.key,
    required this.count,
    this.color,
    this.backgroundColor,
    this.size = 16,
  })  : label = null,
        isDot = false;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final bg = backgroundColor ?? color ?? AppColors.accentFor(brightness);
    final fg = color != null
        ? Colors.white
        : AppColors.onAccentContainerFor(brightness);

    if (isDot) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
        ),
      );
    }

    final text = label ?? (count != null ? count.toString() : '');
    const maxCount = 99;
    final displayText = count != null && count! > maxCount ? '99+' : text;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal:
            displayText.length == 1 ? AppDimens.space6 : AppDimens.space4,
        vertical: AppDimens.space1,
      ),
      constraints: BoxConstraints(
        minWidth: size,
        minHeight: size,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
      ),
      child: Center(
        child: Text(
          displayText,
          style: AppTextStyle.caption2.copyWith(
            color: fg,
            fontWeight: FontWeight.w700,
            fontSize: size * 0.7,
          ),
        ),
      ),
    );
  }
}

/// Status indicator (online, busy, away, etc.).
class NexaStatusIndicator extends StatelessWidget {
  final NexaStatus status;
  final double size;
  final bool showBorder;

  const NexaStatusIndicator({
    super.key,
    required this.status,
    this.size = 12,
    this.showBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final surface = AppColors.surfaceFor(brightness);

    Color color;
    switch (status) {
      case NexaStatus.online:
        color = AppColors.successFor(brightness);
      case NexaStatus.busy:
        color = AppColors.errorFor(brightness);
      case NexaStatus.away:
        color = AppColors.warningFor(brightness);
      case NexaStatus.offline:
        color = AppColors.labelTertiaryFor(brightness);
      case NexaStatus.syncing:
        color = AppColors.accentFor(brightness);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border:
            showBorder ? Border.all(color: surface, width: size * 0.25) : null,
      ),
    );
  }
}

enum NexaStatus { online, busy, away, offline, syncing }
