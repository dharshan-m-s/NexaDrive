import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';

/// One UI empty / offline / error state.
///
/// Soft icon tile + title + one-line hint + optional primary action.
/// Follows One UI's human writing: say what happened, then say what to do.
class OneUiEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? hint;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? secondary;

  const OneUiEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
    this.actionLabel,
    this.onAction,
    this.secondary,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final accent = AppColors.accentFor(brightness);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.space32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: brightness == Brightness.dark
                    ? accent.withValues(alpha: 0.16)
                    : accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppDimens.radiusCard),
              ),
              child: Icon(icon, size: 36, color: accent),
            ),
            const SizedBox(height: AppDimens.space20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyle.sectionHeader.copyWith(
                color: AppColors.textPrimaryFor(brightness),
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: AppDimens.space8),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: AppTextStyle.rowSubtitle.copyWith(
                  color: AppColors.textSecondaryFor(brightness),
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppDimens.space20),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add_rounded, size: AppDimens.iconSmall),
                label: Text(actionLabel!),
              ),
            ],
            if (secondary != null) ...[
              const SizedBox(height: AppDimens.space12),
              secondary!,
            ],
          ],
        ),
      ),
    );
  }
}

/// A compact One UI "Donut-style" progress tile used in Home storage rows and
/// offline queue summaries. Not a giant ring — a slim labeled progress row.
class OneUiProgressTile extends StatelessWidget {
  final String title;
  final String label;
  final String detail;
  final double value; // 0.0 .. 1.0
  final Widget? leading;

  const OneUiProgressTile({
    super.key,
    required this.title,
    required this.label,
    required this.detail,
    required this.value,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final accent = AppColors.accentFor(brightness);
    final secondary = AppColors.textSecondaryFor(brightness);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.space16, AppDimens.space16, AppDimens.space16, AppDimens.space20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: AppDimens.space12)],
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyle.sectionHeader.copyWith(
                    color: AppColors.textPrimaryFor(brightness),
                  ),
                ),
              ),
              Text(
                label,
                style: AppTextStyle.caption.copyWith(color: secondary),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.space12),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppDimens.radiusPill),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: brightness == Brightness.dark
                  ? AppColors.surfaceAltDark
                  : AppColors.surfaceAltLight,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          const SizedBox(height: AppDimens.space8),
          Text(
            detail,
            style: AppTextStyle.micro.copyWith(color: secondary),
          ),
        ],
      ),
    );
  }
}