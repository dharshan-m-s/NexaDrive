import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';

/// One UI grouped list pattern.
///
/// A column of [OneUiGroupTile]s inside a softly-rounded surface panel.
/// This is the defining One UI list rhythm — grouped focus blocks with
/// restrained dividers, NOT endless floating cards.
class OneUiGroupedList extends StatelessWidget {
  final String? header;
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;
  final bool withDividers;
  final Widget? footer;

  const OneUiGroupedList({
    super.key,
    this.header,
    required this.children,
    this.padding,
    this.withDividers = true,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final surface = brightness == Brightness.dark
        ? AppColors.surfaceDark
        : AppColors.surfaceLight;
    final divider = AppColors.dividerFor(brightness);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.space4, AppDimens.space8, AppDimens.space4, AppDimens.space8,
            ),
            child: Text(
              header!.toUpperCase(),
              style: AppTextStyle.listHeader.copyWith(
                color: AppColors.textTertiaryFor(brightness),
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
        Container(
          padding: padding ?? const EdgeInsets.symmetric(vertical: AppDimens.space4),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(AppDimens.radiusCard),
            // A soft lift separates the panel from the page background. On
            // deep black this needs a hairline border in addition to the
            // shadow or the group reads as plain floating text (One UI's
            // flat grouped lists only read correctly against its tonal
            // surfaces, which this theme deliberately shifts for legibility).
            boxShadow: brightness == Brightness.dark
                ? const [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 18,
                      offset: Offset(0, 6),
                    ),
                  ]
                : const [
                    BoxShadow(
                      color: AppColors.shadowColorSoft,
                      blurRadius: 20,
                      offset: Offset(0, 6),
                    ),
                  ],
            border: brightness == Brightness.dark
                ? Border.all(color: const Color(0x1FFFFFFF))
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  children[i],
                  if (withDividers && i < children.length - 1)
                    Padding(
                      padding: EdgeInsets.only(
                        left: _insetFor(children[i]),
                        right: AppDimens.space16,
                      ),
                      child: Divider(color: divider, height: 1),
                    ),
                ],
              ],
            ),
          ),
        ),
        if (footer != null) ...[
          const SizedBox(height: AppDimens.space12),
          footer!,
        ],
        const SizedBox(height: AppDimens.space4),
      ],
    );
  }

  /// Dividers skip the leading icon when the tile shows one.
  static double _insetFor(Widget child) {
    if (child is OneUiGroupTile && child.iconDividerInset) {
      return AppDimens.space16 + AppDimens.iconTileLarge + AppDimens.space12;
    }
    return AppDimens.space16;
  }
}

/// A single row inside a [OneUiGroupedList].
///
/// Optional leading icon-tile, title, subtitle, trailing widget.
class OneUiGroupTile extends StatelessWidget {
  final IconData? icon;
  final Color? iconColor;
  final Color? iconBackground;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? leading;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool showChevron;
  final bool enabled;
  final bool selected;
  final bool iconDividerInset;
  final Key? actionKey;

  const OneUiGroupTile({
    super.key,
    this.icon,
    this.iconColor,
    this.iconBackground,
    required this.title,
    this.subtitle,
    this.trailing,
    this.leading,
    this.onTap,
    this.onLongPress,
    this.showChevron = true,
    this.enabled = true,
    this.selected = false,
    this.iconDividerInset = true,
    this.actionKey,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final onSurface = AppColors.textPrimaryFor(brightness);
    final secondary = AppColors.textSecondaryFor(brightness);
    final accent = AppColors.accentFor(brightness);

    final leadingWidget = leading ??
        (icon == null
            ? null
            : _IconTile(
                icon: icon!,
                iconColor: iconColor ?? accent,
                background: iconBackground ??
                    (brightness == Brightness.dark
                        ? accent.withValues(alpha: 0.18)
                        : accent.withValues(alpha: 0.12)),
              ));

    return ListTile(
      enabled: enabled,
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
      selectedTileColor: accent.withValues(alpha: 0.10),
      minTileHeight: AppDimens.listHeight,
      leading: leadingWidget,
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyle.rowTitle.copyWith(
          color: enabled ? onSurface : AppColors.textTertiaryFor(brightness),
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.caption.copyWith(color: secondary),
            ),
      trailing: trailing ??
          (showChevron
              ? Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textTertiaryFor(brightness),
                  size: AppDimens.iconMedium,
                )
              : null),
    );
  }
}

/// Soft rounded tile that hosts a category icon.
class _IconTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color background;

  const _IconTile({
    required this.icon,
    required this.iconColor,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppDimens.iconTileLarge,
      height: AppDimens.iconTileLarge,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppDimens.radiusInner),
      ),
      child: Icon(icon, color: iconColor, size: AppDimens.iconMedium),
    );
  }
}

/// A compact information row used in detail panels.
class OneUiInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Widget? leading;
  final Color? valueColor;

  const OneUiInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.leading,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space16, vertical: AppDimens.space12,
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: AppDimens.space12)],
          Expanded(
            child: Text(
              label,
              style: AppTextStyle.caption
                  .copyWith(color: AppColors.textSecondaryFor(brightness)),
            ),
          ),
          Text(
            value,
            style: AppTextStyle.rowSubtitle.copyWith(
              color: valueColor ?? AppColors.textPrimaryFor(brightness),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}