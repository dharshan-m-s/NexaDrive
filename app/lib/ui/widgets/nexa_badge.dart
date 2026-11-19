import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';

/// Small Material 3 status badge (dot, count, label).
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
    this.size = AppDimens.space8,
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
    final scheme = Theme.of(context).colorScheme;
    final bg = backgroundColor ?? color ?? scheme.primary;
    final fg = scheme.onPrimary;

    if (isDot) {
      return Semantics(
        label: 'New activity',
        child: Container(
          width: size,
          height: size,
          decoration: ShapeDecoration(
            color: bg,
            shape: const CircleBorder(),
          ),
        ),
      );
    }

    final text = label ?? (count != null ? count.toString() : '');
    const maxCount = 99;
    final displayText = count != null && count! > maxCount ? '99+' : text;

    return Semantics(
      label: displayText,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal:
              displayText.length == 1 ? AppDimens.space6 : AppDimens.space4,
          vertical: AppDimens.space1,
        ),
        constraints: BoxConstraints(
          minWidth: size,
          minHeight: size,
        ),
        decoration: ShapeDecoration(
          color: bg,
          shape: const StadiumBorder(),
        ),
        child: Center(
          child: Text(
            displayText,
            style: AppTextStyle.labelSmall.copyWith(color: fg),
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

  /// Optional explicit border. When omitted, [showBorder] derives a tonal
  /// surface-coloured border from the current [ColorScheme].
  final BorderSide? side;

  const NexaStatusIndicator({
    super.key,
    required this.status,
    this.size = 12,
    this.showBorder = true,
    this.side,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = scheme.brightness;

    Color color;
    switch (status) {
      case NexaStatus.online:
        color = AppColors.successFor(brightness);
      case NexaStatus.busy:
        color = scheme.error;
      case NexaStatus.away:
        color = AppColors.warningFor(brightness);
      case NexaStatus.offline:
        color = scheme.onSurfaceVariant;
      case NexaStatus.syncing:
        color = scheme.primary;
    }

    final borderSide = side ??
        (showBorder
            ? BorderSide(color: scheme.surfaceContainer, width: 2)
            : BorderSide.none);

    return Semantics(
      label: status.name,
      container: true,
      child: Container(
        width: size,
        height: size,
        decoration: ShapeDecoration(
          color: color,
          shape: CircleBorder(side: borderSide),
        ),
      ),
    );
  }
}

enum NexaStatus { online, busy, away, offline, syncing }
