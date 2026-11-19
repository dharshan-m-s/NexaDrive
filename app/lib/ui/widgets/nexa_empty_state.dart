import 'package:flutter/material.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';
import 'nexa_button.dart';

/// Layered tonal artwork for empty states — no optical glass or heavy shadows.
class _EmptyIllustration extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color accent;

  const _EmptyIllustration({
    required this.icon,
    required this.size,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: SizedBox(
        width: size + AppDimens.space20,
        height: size + AppDimens.space20,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: AppDimens.space2,
              top: AppDimens.space6,
              child: Transform.rotate(
                angle: -0.12,
                child: Container(
                  width: size * 0.84,
                  height: size * 0.84,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(AppDimens.radiusMedium),
                  ),
                ),
              ),
            ),
            Positioned(
              right: AppDimens.space2,
              bottom: AppDimens.space4 + AppDimens.space1,
              child: Transform.rotate(
                angle: 0.10,
                child: Container(
                  width: size * 0.84,
                  height: size * 0.84,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(AppDimens.radiusMedium),
                  ),
                ),
              ),
            ),
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppDimens.radiusLarge),
              ),
              child: Icon(icon, size: size * 0.45, color: accent),
            ),
          ],
        ),
      ),
    );
  }
}

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
    this.iconSize = 52,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space32,
        vertical: AppDimens.space16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _EmptyIllustration(
            icon: icon,
            size: iconSize,
            accent: scheme.primary,
          ),
          const SizedBox(height: AppDimens.space12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTextStyle.headlineSmall.copyWith(color: scheme.onSurface),
          ),
          if (hint != null) ...[
            const SizedBox(height: AppDimens.space4),
            Text(
              hint!,
              textAlign: TextAlign.center,
              style: AppTextStyle.bodyMedium.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppDimens.space12),
            NexaTextButton(
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
