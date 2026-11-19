import 'package:flutter/material.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';
import 'nexa_button.dart';

/// Layered tonal artwork for error states — semantic error container, no shadow.
class _ErrorIllustration extends StatelessWidget {
  final IconData icon;
  final Color error;
  final Color surface;
  final Color container;

  const _ErrorIllustration({
    required this.icon,
    required this.error,
    required this.surface,
    required this.container,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 82,
      height: 82,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: AppDimens.space2,
            top: AppDimens.space6 + AppDimens.space1,
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(AppDimens.radiusLarge),
              ),
            ),
          ),
          Positioned(
            right: AppDimens.space1,
            bottom: AppDimens.space4,
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: container,
                borderRadius: BorderRadius.circular(AppDimens.radiusLarge),
              ),
            ),
          ),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(AppDimens.radiusCard),
            ),
            child: Icon(icon, size: AppDimens.iconLarge, color: error),
          ),
        ],
      ),
    );
  }
}

/// Error state with retry action.
class NexaErrorState extends StatelessWidget {
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData icon;
  final bool centered;

  const NexaErrorState({
    super.key,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.icon = Icons.error_outline_rounded,
    this.centered = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space32,
        vertical: AppDimens.space24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ErrorIllustration(
            icon: icon,
            error: scheme.error,
            surface: scheme.surfaceContainerLow,
            container: scheme.errorContainer,
          ),
          const SizedBox(height: AppDimens.space16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTextStyle.titleMedium.copyWith(color: scheme.onSurface),
          ),
          if (message != null) ...[
            const SizedBox(height: AppDimens.space8),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: AppTextStyle.bodyMedium.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppDimens.space20),
            NexaFilledButton(
              onPressed: onAction,
              icon:
                  const Icon(Icons.refresh_rounded, size: AppDimens.iconSmall),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );

    if (!centered) return content;
    return Center(child: content);
  }
}

/// Full-screen error state for use in scrollable lists.
class NexaErrorStateFullScreen extends StatelessWidget {
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData icon;

  const NexaErrorStateFullScreen({
    super.key,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.icon = Icons.error_outline_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.3),
        NexaErrorState(
          title: title,
          message: message,
          actionLabel: actionLabel,
          onAction: onAction,
          icon: icon,
          centered: true,
        ),
      ],
    );
  }
}
