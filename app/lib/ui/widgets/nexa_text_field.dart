import 'package:flutter/material.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';

/// NexaDrive form field — a Material 3 filled [TextFormField].
///
/// Colours, outline, shape and state layers come from the theme's
/// [InputDecorationTheme]; the field only supplies content and icon theming.
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

  /// Compatibility alias for [onSubmitted], used by existing call sites.
  final ValueChanged<String>? onFieldSubmitted;
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
    this.onFieldSubmitted,
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

  FocusNode get _activeFocusNode => widget.focusNode ?? _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _activeFocusNode.addListener(_onFocusChange);
    _hasFocus = _activeFocusNode.hasFocus;
  }

  @override
  void didUpdateWidget(covariant NexaTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _focusNode).removeListener(_onFocusChange);
      _activeFocusNode.addListener(_onFocusChange);
      _hasFocus = _activeFocusNode.hasFocus;
    }
  }

  @override
  void dispose() {
    _activeFocusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    setState(() => _hasFocus = _activeFocusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return TextFormField(
      controller: widget.controller,
      focusNode: _activeFocusNode,
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
      onFieldSubmitted: widget.onFieldSubmitted ?? widget.onSubmitted,
      validator: widget.validator,
      style: AppTextStyle.bodyLarge.copyWith(color: scheme.onSurface),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        helperText: widget.helperText,
        errorText: widget.errorText,
        counterText: '',
        isDense: widget.dense,
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppDimens.space16,
          vertical: widget.dense ? AppDimens.space8 : AppDimens.space16,
        ),
        hintStyle: AppTextStyle.bodyLarge.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        helperStyle: AppTextStyle.bodySmall.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        errorStyle: AppTextStyle.bodySmall.copyWith(color: scheme.error),
        prefixIcon: widget.prefixIcon != null
            ? Padding(
                padding: const EdgeInsets.only(
                  left: AppDimens.space12,
                  right: AppDimens.space8,
                ),
                child: IconTheme(
                  data: IconThemeData(
                    size: AppDimens.iconMedium,
                    color: _hasFocus ? scheme.primary : scheme.onSurfaceVariant,
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
                    color: scheme.onSurfaceVariant,
                  ),
                  child: widget.suffixIcon!,
                ),
              )
            : null,
      ),
    );
  }
}
