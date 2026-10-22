import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_motion.dart';
import '../../core/design/app_typography.dart';

/// Reveals a bar by sliding it in and fading it, so entering and leaving a mode
/// (selection, breadcrumb, a pinned action) reads as a settle instead of the
/// element slamming in and jumping the content around it.
///
/// Its height animates too, so neighbouring content grows and shrinks smoothly
/// to make room. [alignment] anchors the reveal: [Alignment.bottomLeft] rises
/// from the bottom (the default, for a bottom action bar); [Alignment.topLeft]
/// descends from the top (for a breadcrumb or top bar). Reduced motion shows
/// and hides it instantly.
class NexaRevealBar extends StatelessWidget {
  const NexaRevealBar({
    super.key,
    required this.visible,
    required this.child,
    this.alignment = Alignment.bottomLeft,
  });

  final bool visible;
  final Widget child;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.resolve(context, AppMotion.normal),
      reverseDuration: AppMotion.resolve(context, AppMotion.fast),
      switchInCurve: AppMotion.curveFor(context, AppMotion.standardCurve),
      switchOutCurve: AppMotion.curveFor(context, AppMotion.standardCurve),
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation,
        alignment: alignment,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: visible
          ? KeyedSubtree(key: const ValueKey('shown'), child: child)
          : const SizedBox.shrink(key: ValueKey('hidden')),
    );
  }
}

/// Contextual action bar (appears during selection).
class NexaActionBar extends StatelessWidget {
  final Widget? leading;
  final String title;
  final List<NexaActionItem> actions;
  final Color? backgroundColor;

  const NexaActionBar({
    super.key,
    this.leading,
    required this.title,
    required this.actions,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final bg = backgroundColor ?? AppColors.surfaceFor(brightness);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.pageMargin,
        vertical: AppDimens.space8,
      ),
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          top: BorderSide(
            color: AppColors.separatorFor(brightness),
            width: 0.5,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowColorFor(brightness),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: AppDimens.space12),
            ],
            Expanded(
              child: Text(
                title,
                style: AppTextStyle.title1.copyWith(
                  color: AppColors.labelPrimaryFor(brightness),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ...actions.map((action) => Padding(
                  padding: const EdgeInsets.only(left: AppDimens.space8),
                  child: action,
                )),
          ],
        ),
      ),
    );
  }
}

class NexaActionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;
  final bool isDestructive;
  final bool enabled;

  const NexaActionItem({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.color,
    this.isDestructive = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final fg = isDestructive
        ? AppColors.errorFor(brightness)
        : (color ?? AppColors.accentFor(brightness));
    final bg = isDestructive
        ? AppColors.errorContainerFor(brightness)
        : AppColors.fillFor(brightness);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.space12,
            vertical: AppDimens.space8,
          ),
          decoration: BoxDecoration(
            color: enabled ? bg : bg.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: AppDimens.iconSmall,
                  color: enabled ? fg : fg.withValues(alpha: 0.5)),
              const SizedBox(width: AppDimens.space8),
              Text(
                label,
                style: AppTextStyle.caption1.copyWith(
                  color: enabled ? fg : fg.withValues(alpha: 0.5),
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

/// Icon-only action item for dense toolbars.
class NexaIconActionItem extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? color;
  final bool enabled;

  const NexaIconActionItem({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.color,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final fg = color ?? AppColors.labelSecondaryFor(brightness);

    return IconButton(
      onPressed: enabled ? onTap : null,
      icon: Icon(icon,
          size: AppDimens.iconMedium,
          color: enabled ? fg : fg.withValues(alpha: 0.5)),
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: Colors.transparent,
        minimumSize: const Size(AppDimens.touchTarget, AppDimens.touchTarget),
        padding: const EdgeInsets.all(AppDimens.space8),
      ),
    );
  }
}
