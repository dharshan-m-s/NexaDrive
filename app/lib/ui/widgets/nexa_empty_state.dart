import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';
import 'nexa_button.dart';

class _EmptyIllustration extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color accent;
  final Brightness brightness;

  const _EmptyIllustration({required this.icon, required this.size, required this.accent, required this.brightness});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: size + 20,
        height: size + 20,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: 2,
              top: 6,
              child: Transform.rotate(
                angle: -0.12,
                child: Container(
                  width: size * 0.84,
                  height: size * 0.84,
                  decoration: BoxDecoration(
                    color: AppColors.fillFor(brightness),
                    borderRadius: BorderRadius.circular(AppDimens.radiusMedium),
                    border: Border.all(color: AppColors.separatorFor(brightness)),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 2,
              bottom: 5,
              child: Transform.rotate(
                angle: 0.10,
                child: Container(
                  width: size * 0.84,
                  height: size * 0.84,
                  decoration: BoxDecoration(
                    color: AppColors.accentContainerFor(brightness),
                    borderRadius: BorderRadius.circular(AppDimens.radiusMedium),
                  ),
                ),
              ),
            ),
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: AppColors.surfaceFor(brightness),
                borderRadius: BorderRadius.circular(AppDimens.radiusLarge),
                border: Border.all(color: AppColors.separatorFor(brightness), width: 0.8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: brightness == Brightness.dark ? 0.16 : 0.045),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
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
    final brightness = Theme.of(context).brightness;
    final accent = AppColors.accentFor(brightness);

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
            accent: accent,
            brightness: brightness,
          ),
          const SizedBox(height: AppDimens.space12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTextStyle.title3.copyWith(
              color: AppColors.labelPrimaryFor(brightness),
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: AppDimens.space4),
            Text(
              hint!,
              textAlign: TextAlign.center,
              style: AppTextStyle.subheadline.copyWith(
                color: AppColors.labelSecondaryFor(brightness),
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
