import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';

/// NexaDrive text field — iOS-style rounded field with proper states.
class NexaTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? helperText;
  final String? errorText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final bool readOnly;
  final bool enabled;
  final bool autofocus;
  final FocusNode? focusNode;
  final int? maxLines;
  final int? maxLength;
  final List<String>? autofillHints;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;
  final TextCapitalization textCapitalization;

  /// Reduces the vertical padding for dense, short-viewport layouts.
  final bool dense;

  const NexaTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.helperText,
    this.errorText,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.readOnly = false,
    this.enabled = true,
    this.autofocus = false,
    this.focusNode,
    this.maxLines = 1,
    this.maxLength,
    this.autofillHints,
    this.prefixIcon,
    this.suffixIcon,
    this.onTap,
    this.onChanged,
    this.onSubmitted,
    this.validator,
    this.textCapitalization = TextCapitalization.none,
    this.dense = false,
  });

  @override
  State<NexaTextField> createState() => _NexaTextFieldState();
}

class _NexaTextFieldState extends State<NexaTextField> {
  late FocusNode _focusNode;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    setState(() => _hasFocus = _focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final hasError = widget.errorText != null;
    final accent = AppColors.accentFor(brightness);
    final error = AppColors.errorFor(brightness);
    final fillColor = AppColors.fillFor(brightness);
    final borderColor = hasError
        ? error
        : _hasFocus
            ? accent
            : Colors.transparent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Padding(
            padding: const EdgeInsets.only(
                left: AppDimens.space4, bottom: AppDimens.space6),
            child: Text(
              widget.label!,
              style: AppTextStyle.caption1.copyWith(
                color: AppColors.labelSecondaryFor(brightness),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        TextFormField(
          controller: widget.controller,
          focusNode: widget.focusNode ?? _focusNode,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          obscureText: widget.obscureText,
          readOnly: widget.readOnly,
          enabled: widget.enabled,
          autofocus: widget.autofocus,
          maxLines: widget.maxLines,
          maxLength: widget.maxLength,
          autofillHints: widget.autofillHints,
          textCapitalization: widget.textCapitalization,
          onTap: widget.onTap,
          onChanged: widget.onChanged,
          onFieldSubmitted: widget.onSubmitted,
          validator: widget.validator,
          style: AppTextStyle.body.copyWith(
            color: AppColors.labelPrimaryFor(brightness),
          ),
          decoration: InputDecoration(
            hintText: widget.hint,
            helperText: widget.helperText,
            errorText: widget.errorText,
            counterText: '',
            filled: true,
            fillColor: fillColor,
            isDense: true,
            contentPadding: EdgeInsets.symmetric(
              horizontal: AppDimens.space16,
              vertical: widget.dense ? AppDimens.space8 : AppDimens.space12,
            ),
            hintStyle: AppTextStyle.body.copyWith(
              color: AppColors.labelTertiaryFor(brightness),
            ),
            helperStyle: AppTextStyle.caption2.copyWith(
              color: AppColors.labelTertiaryFor(brightness),
            ),
            errorStyle: AppTextStyle.caption2.copyWith(
              color: error,
            ),
            prefixIcon: widget.prefixIcon != null
                ? Padding(
                    padding: const EdgeInsets.only(
                        left: AppDimens.space12, right: AppDimens.space8),
                    child: IconTheme(
                      data: IconThemeData(
                        size: AppDimens.iconMedium,
                        color: _hasFocus
                            ? accent
                            : AppColors.labelTertiaryFor(brightness),
                      ),
                      child: widget.prefixIcon!,
                    ),
                  )
                : null,
            suffixIcon: widget.suffixIcon != null
                ? Padding(
                    padding: const EdgeInsets.only(right: AppDimens.space12),
                    child: IconTheme(
                      data: IconThemeData(
                        size: AppDimens.iconMedium,
                        color: AppColors.labelTertiaryFor(brightness),
                      ),
                      child: widget.suffixIcon!,
                    ),
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
              borderSide: BorderSide(
                  color: borderColor, width: _hasFocus || hasError ? 2 : 0),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
              borderSide: BorderSide(color: accent, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
              borderSide: BorderSide(color: error, width: 2),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
              borderSide: BorderSide(color: error, width: 2),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}
