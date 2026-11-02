import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';
import 'nexa_button.dart';

class _ErrorIllustration extends StatelessWidget {
  final IconData icon;
  final Color error;
  final Brightness brightness;

  const _ErrorIllustration({
    required this.icon,
    required this.error,
    required this.brightness,
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
            left: 2,
            top: 7,
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: AppColors.fillFor(brightness),
                borderRadius: BorderRadius.circular(AppDimens.radiusLarge),
              ),
            ),
          ),
          Positioned(
            right: 1,
            bottom: 4,
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: AppColors.errorContainerFor(brightness),
                borderRadius: BorderRadius.circular(AppDimens.radiusLarge),
              ),
            ),
          ),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.surfaceFor(brightness),
              borderRadius: BorderRadius.circular(AppDimens.radiusXLarge),
              border: Border.all(color: AppColors.separatorFor(brightness)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: brightness == Brightness.dark ? 0.14 : 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, size: 30, color: error),
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
    final brightness = Theme.of(context).brightness;
    final error = AppColors.errorFor(brightness);

    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space32,
        vertical: AppDimens.space24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ErrorIllustration(icon: icon, error: error, brightness: brightness),
          const SizedBox(height: AppDimens.space16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTextStyle.sectionHeader.copyWith(
              color: AppColors.labelPrimaryFor(brightness),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: AppDimens.space8),
            Text(
              message!,
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
