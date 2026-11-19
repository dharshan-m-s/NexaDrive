import 'package:flutter/material.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_motion.dart';
import '../../core/design/app_typography.dart';
import 'nexa_surface.dart';

/// Reveals a bar by sliding it in and fading it, so entering and leaving a mode
/// (selection, breadcrumb, a pinned action) reads as a settle instead of the
/// element slamming in and jumping the content around it.
///
/// Its height animates too, so neighbouring content grows and shrinks smoothly
/// to make room. [alignment] anchors the reveal. Reduced motion shows and hides
/// it instantly.
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

/// Space between a contextual bar and the floating pill.
///
/// The shell reports the pill's full footprint through `MediaQuery.padding.bottom`.
/// The bar itself only needs to clear the pill's top edge; keeping the whole
/// footprint as internal padding would leave a large empty strip in the bar.
double nexaContextualBarBottomPadding(BuildContext context) =>
    (MediaQuery.paddingOf(context).bottom - AppDimens.space24)
        .clamp(0.0, double.infinity);

/// Material 3 contextual action bar (appears during selection).
class NexaActionBar extends StatelessWidget {
  final Widget? leading;
  final String title;
  final List<NexaActionItem> actions;
  final Color? backgroundColor;

  /// Lifts the bar just above the floating pill on mobile destinations.
  final bool aboveFloatingNav;

  const NexaActionBar({
    super.key,
    this.leading,
    required this.title,
    required this.actions,
    this.backgroundColor,
    this.aboveFloatingNav = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final bottom =
        aboveFloatingNav ? nexaContextualBarBottomPadding(context) : 0.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppDimens.pageMargin,
        AppDimens.space6,
        AppDimens.pageMargin,
        AppDimens.space8 + bottom,
      ),
      child: NexaSurface(
        level: NexaSurfaceLevel.floating,
        color: backgroundColor,
        radius: AppDimens.radiusMedium,
        padding: const EdgeInsets.fromLTRB(
          AppDimens.space8,
          AppDimens.space6,
          AppDimens.space8,
          AppDimens.space6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: AppDimens.space8),
                ],
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.titleMedium.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: AppDimens.space4),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final action in actions)
                      Padding(
                        padding: const EdgeInsets.only(right: AppDimens.space6),
                        child: action,
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Material 3 action chip used inside a contextual action bar.
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
    final scheme = Theme.of(context).colorScheme;
    final fg = isDestructive ? scheme.error : (color ?? scheme.primary);
    final bg =
        isDestructive ? scheme.errorContainer : scheme.surfaceContainerHighest;
    final effectiveFg = enabled ? fg : scheme.onSurface.withValues(alpha: 0.38);

    final chipTheme = Theme.of(context).chipTheme.copyWith(
          backgroundColor: bg,
          disabledColor: scheme.surfaceContainer.withValues(alpha: 0.5),
          side: BorderSide.none,
          shape: const StadiumBorder(),
          labelStyle: AppTextStyle.labelMedium.copyWith(color: effectiveFg),
        );

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
      child: ChipTheme(
        data: chipTheme,
        child: ActionChip(
          avatar: Icon(icon, size: AppDimens.iconSmall, color: effectiveFg),
          label: Text(
            label,
            style: AppTextStyle.labelMedium.copyWith(color: effectiveFg),
          ),
          onPressed: enabled ? onTap : null,
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
    final scheme = Theme.of(context).colorScheme;
    final fg = color ?? scheme.onSurfaceVariant;

    return IconButton(
      onPressed: enabled ? onTap : null,
      icon: Icon(
        icon,
        size: AppDimens.iconMedium,
        color: enabled ? fg : fg.withValues(alpha: 0.38),
      ),
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: Colors.transparent,
        minimumSize: const Size(AppDimens.touchTarget, AppDimens.touchTarget),
        padding: const EdgeInsets.all(AppDimens.space8),
        shape: const StadiumBorder(),
      ),
    );
  }
}
