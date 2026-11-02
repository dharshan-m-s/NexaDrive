import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';
import 'nexa_button.dart';

/// Standard empty state with illustration, title, hint, and action.
class NexaEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? hint;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? secondary;
  final bool centered;
  final IconData actionIcon;
  final double iconSize;

  const NexaEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
    this.actionLabel,
    this.onAction,
    this.secondary,
    this.centered = false,
    this.actionIcon = Icons.add_rounded,
    this.iconSize = 64,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final accent = AppColors.accentFor(brightness);

    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space32,
        vertical: AppDimens.space24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: iconSize,
            height: iconSize,
            decoration: BoxDecoration(
              color: brightness == Brightness.dark
                  ? accent.withValues(alpha: 0.16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppDimens.radiusXLarge),
            ),
            child: Icon(icon, size: iconSize * 0.45, color: accent),
          ),
          const SizedBox(height: AppDimens.space16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTextStyle.sectionHeader.copyWith(
              color: AppColors.labelPrimaryFor(brightness),
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: AppDimens.space8),
            Text(
              hint!,
              textAlign: TextAlign.center,
              style: AppTextStyle.caption1.copyWith(
                color: AppColors.labelSecondaryFor(brightness),
              ),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppDimens.space20),
            NexaFilledButton(
              onPressed: onAction,
              icon: Icon(actionIcon, size: AppDimens.iconSmall),
              child: Text(actionLabel!),
            ),
          ],
          if (secondary != null) ...[
            const SizedBox(height: AppDimens.space12),
            secondary!,
          ],
        ],
      ),
    );

    if (!centered) return content;
    return Center(child: content);
  }
}

/// Full-screen empty state for use in scrollable lists.
class NexaEmptyStateFullScreen extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? hint;
  final String? actionLabel;
  final VoidCallback? onAction;

  const NexaEmptyStateFullScreen({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.3,
        ),
        NexaEmptyState(
          icon: icon,
          title: title,
          hint: hint,
          actionLabel: actionLabel,
          onAction: onAction,
          centered: true,
        ),
      ],
    );
  }
}

/// Pull-to-refresh wrapper with empty state.
class NexaRefreshableEmptyState extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final IconData icon;
  final String title;
  final String? hint;
  final String? actionLabel;
  final VoidCallback? onAction;

  const NexaRefreshableEmptyState({
    super.key,
    required this.onRefresh,
    required this.icon,
    required this.title,
    this.hint,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: NexaEmptyStateFullScreen(
        icon: icon,
        title: title,
        hint: hint,
        actionLabel: actionLabel,
        onAction: onAction,
      ),
    );
  }
}
