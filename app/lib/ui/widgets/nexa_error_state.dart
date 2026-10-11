import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';
import 'nexa_button.dart';

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
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: error.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppDimens.radiusXLarge),
            ),
            child: Icon(icon, size: 30, color: error),
          ),
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
