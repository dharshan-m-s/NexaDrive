import 'package:flutter/material.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';

/// Compact, theme-aware search control for inline discovery.
///
/// A Material 3 filled [TextField] with the theme's search-bar pill shape and
/// surface container tone. The clear action is an [IconButton] with a tooltip.
class NexaSearchField extends StatelessWidget {
  final TextEditingController? controller;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final VoidCallback? onClear;
  final bool autofocus;
  final bool filled;
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
    this.filled = true,
    this.readOnly = false,
    this.showCancel = false,
    this.cancelText = 'Cancel',
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            autofocus: autofocus,
            readOnly: readOnly,
            onChanged: onChanged,
            onTap: onTap,
            style: AppTextStyle.bodyLarge.copyWith(color: scheme.onSurface),
            decoration: InputDecoration(
              hintText: hint ?? 'Search',
              hintStyle: AppTextStyle.bodyLarge.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              filled: filled,
              fillColor:
                  filled ? scheme.surfaceContainerHigh : Colors.transparent,
              prefixIcon: Padding(
                padding: const EdgeInsets.only(
                  left: AppDimens.space12,
                  right: AppDimens.space8,
                ),
                child: Icon(
                  Icons.search_rounded,
                  size: AppDimens.iconMedium,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              suffixIcon: controller != null &&
                      controller!.text.isNotEmpty &&
                      onClear != null
                  ? IconButton(
                      icon: Icon(
                        Icons.clear_rounded,
                        size: AppDimens.iconSmall,
                        color: scheme.onSurfaceVariant,
                      ),
                      onPressed: onClear,
                      tooltip: 'Clear',
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppDimens.space16,
                vertical: AppDimens.space12,
              ),
              border: _pillBorder(BorderSide.none),
              enabledBorder: _pillBorder(BorderSide.none),
              focusedBorder: _pillBorder(
                BorderSide(color: scheme.primary, width: 2),
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
              style: AppTextStyle.labelLarge.copyWith(color: scheme.primary),
            ),
          ),
        ],
      ],
    );
  }

  OutlineInputBorder _pillBorder(BorderSide side) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        borderSide: side,
      );
}
