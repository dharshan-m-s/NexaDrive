import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';

/// A contextual action (icon + short label) for the One UI action bar.
class OneUiActionItem {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;
  final bool enabled;

  const OneUiActionItem({
    required this.icon,
    required this.label,
    this.onTap,
    this.color,
    this.enabled = true,
  });
}

/// One UI "action bar" — the bottom contextual bar used in selection mode
/// and rich screens. Actions sit in the interaction area (bottom), reachable,
/// each a quietly tinted pill that presses to a tonal state.
class OneUiActionBar extends StatelessWidget {
  final String? title;
  final Widget? leading;
  final List<OneUiActionItem> actions;
  final bool floating;

  const OneUiActionBar({
    super.key,
    this.title,
    this.leading,
    required this.actions,
    this.floating = false,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final barSurface = brightness == Brightness.dark
        ? AppColors.surfaceElevatedDark
        : AppColors.surfaceElevatedLight;

    final bar = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space16,
        vertical: AppDimens.space10,
      ),
      decoration: BoxDecoration(
        color: barSurface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(floating ? AppDimens.radiusCard : AppDimens.radiusSheet),
        ),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowColorStrong,
            blurRadius: 24,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Row(
          children: [
            if (title != null || leading != null) ...[
              if (leading != null) leading!,
              if (title != null) ...[
                const SizedBox(width: AppDimens.space12),
                Text(
                  title!,
                  style: AppTextStyle.sectionHeader.copyWith(
                    color: AppColors.textPrimaryFor(brightness),
                  ),
                ),
              ],
              const SizedBox(width: AppDimens.space12),
              Container(
                width: 1,
                height: 32,
                color: AppColors.dividerFor(brightness),
              ),
              const SizedBox(width: AppDimens.space12),
            ],
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final action in actions) ...[
                      _Action(action: action),
                      if (action != actions.last) const SizedBox(width: AppDimens.space8),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (!floating) return bar;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.space16, 0, AppDimens.space16, AppDimens.space12,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: bar,
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  final OneUiActionItem action;
  const _Action({required this.action});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final tint = action.color ?? AppColors.accentTextFor(brightness);
    final onColor = action.enabled ? tint : AppColors.textTertiaryFor(brightness);
    final pillBg = (action.color ?? AppColors.accentSubtleFor(brightness))
        .withValues(alpha: action.color == null ? 1.0 : 0.16);

    return Semantics(
      button: true,
      enabled: action.enabled,
      label: action.label,
      child: InkWell(
        onTap: action.enabled ? action.onTap : null,
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.space16,
            vertical: AppDimens.space8,
          ),
          decoration: BoxDecoration(
            color: pillBg,
            borderRadius: BorderRadius.circular(AppDimens.radiusPill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(action.icon, size: AppDimens.iconSmall, color: onColor),
              const SizedBox(width: AppDimens.space8),
              Text(
                action.label,
                style: AppTextStyle.chipLabel.copyWith(
                  color: onColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}