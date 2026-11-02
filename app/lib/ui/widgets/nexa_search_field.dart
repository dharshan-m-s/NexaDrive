import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';

/// iOS-style search field for inline use.
class NexaSearchField extends StatelessWidget {
  final TextEditingController? controller;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final VoidCallback? onClear;
  final bool autofocus;
  final bool readOnly;
  final bool showCancel;
  final String cancelText;

  const NexaSearchField({
    super.key,
    this.controller,
    this.hint,
    this.onChanged,
    this.onTap,
    this.onClear,
    this.autofocus = false,
    this.readOnly = false,
    this.showCancel = false,
    this.cancelText = 'Cancel',
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final fillColor = AppColors.fillFor(brightness);

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            autofocus: autofocus,
            readOnly: readOnly,
            onChanged: onChanged,
            onTap: onTap,
            style: AppTextStyle.body.copyWith(
              color: AppColors.labelPrimaryFor(brightness),
            ),
            decoration: InputDecoration(
              hintText: hint ?? 'Search',
              hintStyle: AppTextStyle.body.copyWith(
                color: AppColors.labelTertiaryFor(brightness),
              ),
              filled: true,
              fillColor: fillColor,
              prefixIcon: Padding(
                padding: const EdgeInsets.only(
                    left: AppDimens.space12, right: AppDimens.space8),
                child: Icon(
                  Icons.search_rounded,
                  size: AppDimens.iconMedium,
                  color: AppColors.labelTertiaryFor(brightness),
                ),
              ),
              suffixIcon: controller != null &&
                      controller!.text.isNotEmpty &&
                      onClear != null
                  ? IconButton(
                      icon: Icon(
                        Icons.clear_rounded,
                        size: AppDimens.iconSmall,
                        color: AppColors.labelTertiaryFor(brightness),
                      ),
                      onPressed: onClear,
                      tooltip: 'Clear',
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppDimens.space12,
                vertical: AppDimens.space10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                borderSide: BorderSide(
                  color: AppColors.accentFor(brightness),
                  width: 2,
                ),
              ),
            ),
          ),
        ),
        if (showCancel) ...[
          const SizedBox(width: AppDimens.space12),
          TextButton(
            onPressed: onClear ?? () => controller?.clear(),
            child: Text(
              cancelText,
              style: AppTextStyle.buttonSmall.copyWith(
                color: AppColors.accentFor(brightness),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
