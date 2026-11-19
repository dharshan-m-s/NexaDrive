import 'package:flutter/material.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';

/// Semantic Material 3 chip with a consistent tonal fill.
///
/// Interactive chips render a [FilterChip] (checkmark hidden); static status
/// chips render a plain [Chip]. Both take their label style from the Material
/// `labelMedium` role and their shape from the theme's stadium chip shape.
class NexaChip extends StatelessWidget {
  final String label;
  final IconData? leadingIcon;
  final VoidCallback? onTap;
  final bool selected;
  final NexaChipVariant variant;

  /// Optional semantic tint for status chips (success / warning / error).
  /// Pass tonal container/foreground pairs from [AppColors], never raw colours.
  final Color? tintColor;
  final Color? tintForeground;

  const NexaChip({
    super.key,
    required this.label,
    this.leadingIcon,
    this.onTap,
    this.selected = false,
    this.variant = NexaChipVariant.tonal,
    this.tintColor,
    this.tintForeground,
  });

  /// Filled accent chip (primary actions, selected state).
  const NexaChip.filled({
    super.key,
    required this.label,
    this.leadingIcon,
    this.onTap,
    this.selected = false,
    this.tintColor,
    this.tintForeground,
  }) : variant = NexaChipVariant.filled;

  /// Outlined chip (secondary actions).
  const NexaChip.outlined({
    super.key,
    required this.label,
    this.leadingIcon,
    this.onTap,
    this.selected = false,
    this.tintColor,
    this.tintForeground,
  }) : variant = NexaChipVariant.outlined;

  /// Tonal chip (status, categories) — uses the secondary container role.
  const NexaChip.tonal({
    super.key,
    required this.label,
    this.leadingIcon,
    this.onTap,
    this.selected = false,
    this.tintColor,
    this.tintForeground,
  }) : variant = NexaChipVariant.tonal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    late final Color fill;
    late final Color foreground;
    late final BorderSide edge;

    if (tintColor != null) {
      // Semantic status chip: the tint carries the meaning, in both
      // appearances, through the supplied tonal container tokens.
      fill = tintColor!;
      foreground = tintForeground ?? scheme.onSurface;
      edge = BorderSide.none;
    } else {
      switch (variant) {
        case NexaChipVariant.filled:
          fill = selected ? scheme.primary : scheme.primaryContainer;
          foreground = selected ? scheme.onPrimary : scheme.onPrimaryContainer;
          edge = BorderSide.none;
        case NexaChipVariant.outlined:
          fill = Colors.transparent;
          foreground = scheme.primary;
          edge = BorderSide(color: scheme.outline, width: 1);
        case NexaChipVariant.tonal:
          fill = selected
              ? scheme.secondaryContainer
              : scheme.surfaceContainerHigh;
          foreground =
              selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;
          edge = BorderSide.none;
      }
    }

    final labelStyle = AppTextStyle.labelMedium.copyWith(color: foreground);
    final avatar = leadingIcon == null
        ? null
        : Icon(leadingIcon, size: AppDimens.iconSmall);

    final chipTheme = Theme.of(context).chipTheme.copyWith(
          backgroundColor: fill,
          selectedColor: fill,
          side: edge,
          shape: const StadiumBorder(),
          labelStyle: labelStyle,
          secondaryLabelStyle: labelStyle,
        );

    return ChipTheme(
      data: chipTheme,
      child: onTap == null
          ? Chip(
              avatar: avatar,
              label: Text(label, style: labelStyle),
            )
          : FilterChip(
              avatar: avatar,
              label: Text(label, style: labelStyle),
              selected: selected,
              showCheckmark: false,
              onSelected: (_) => onTap!(),
            ),
    );
  }
}

enum NexaChipVariant { filled, outlined, tonal }

/// Section header for grouped lists — a Material 3 overline label.
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
    final scheme = Theme.of(context).colorScheme;
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
                  AppTextStyle.labelMedium.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
