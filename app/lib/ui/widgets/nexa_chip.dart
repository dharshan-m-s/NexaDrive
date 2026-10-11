import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';

/// Semantic badge/chip with consistent styling.
class NexaChip extends StatelessWidget {
  final String label;
  final IconData? leadingIcon;
  final VoidCallback? onTap;
  final bool selected;
  final NexaChipVariant variant;

  const NexaChip({
    super.key,
    required this.label,
    this.leadingIcon,
    this.onTap,
    this.selected = false,
    this.variant = NexaChipVariant.tonal,
  });

  /// Filled accent chip (primary actions, selected state).
  const NexaChip.filled({
    super.key,
    required this.label,
    this.leadingIcon,
    this.onTap,
    this.selected = false,
  }) : variant = NexaChipVariant.filled;

  /// Outlined chip (secondary actions).
  const NexaChip.outlined({
    super.key,
    required this.label,
    this.leadingIcon,
    this.onTap,
    this.selected = false,
  }) : variant = NexaChipVariant.outlined;

  /// Tonal chip (status, categories) — uses accent container.
  const NexaChip.tonal({
    super.key,
    required this.label,
    this.leadingIcon,
    this.onTap,
    this.selected = false,
  }) : variant = NexaChipVariant.tonal;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final accent = AppColors.accentFor(brightness);
    final onAccent = AppColors.onAccentContainerFor(brightness);

    Color bg;
    Color fg;
    BorderSide? border;

    switch (variant) {
      case NexaChipVariant.filled:
        bg = selected ? accent : accent.withValues(alpha: 0.12);
        fg = selected ? onAccent : accent;
        border = BorderSide.none;
      case NexaChipVariant.outlined:
        bg = Colors.transparent;
        fg = accent;
        border = BorderSide(color: accent, width: 1.5);
      case NexaChipVariant.tonal:
        bg = selected
            ? AppColors.accentContainerFor(brightness)
            : AppColors.fillFor(brightness);
        fg = selected ? onAccent : AppColors.labelSecondaryFor(brightness);
        border = BorderSide.none;
    }

    final widget = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space12,
        vertical: AppDimens.space6,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        border:
            border != BorderSide.none ? Border.fromBorderSide(border) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leadingIcon != null) ...[
            Icon(leadingIcon, size: AppDimens.iconSmall, color: fg),
            const SizedBox(width: AppDimens.space6),
          ],
          Text(
            label,
            style: AppTextStyle.caption1.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return widget;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimens.radiusPill),
      child: widget,
    );
  }
}

enum NexaChipVariant { filled, outlined, tonal }

/// Section header for grouped lists.
class NexaSectionHeader extends StatelessWidget {
  final String title;
  final TextStyle? style;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  const NexaSectionHeader(
    this.title, {
    super.key,
    this.style,
    this.trailing,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: padding ??
          const EdgeInsets.fromLTRB(
            AppDimens.space4,
            AppDimens.space12,
            AppDimens.space4,
            AppDimens.space8,
          ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: style ??
                  AppTextStyle.listHeader.copyWith(
                    color: AppColors.labelTertiaryFor(brightness),
                    letterSpacing: 0.8,
                  ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
