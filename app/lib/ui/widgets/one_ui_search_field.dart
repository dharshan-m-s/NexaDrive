import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';

/// One UI search field — a pill, a hint, a clear button, immediate feedback.
///
/// Used in the viewing area as the entry point into focused search mode, and
/// standalone in search surfaces. Keeps its own focus decoration so the
/// field reads as "active" while the search page takes over.
class OneUiSearchField extends StatefulWidget {
  final TextEditingController? controller;
  final String hint;
  final String? labelText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final bool autofocus;

  const OneUiSearchField({
    super.key,
    this.controller,
    this.hint = 'Search',
    this.labelText,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.autofocus = false,
  });

  @override
  State<OneUiSearchField> createState() => _OneUiSearchFieldState();
}

class _OneUiSearchFieldState extends State<OneUiSearchField> {
  late final TextEditingController _owned;
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _owned = TextEditingController();
    _controller = widget.controller ?? _owned;
  }

  @override
  void dispose() {
    _owned.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final scheme = Theme.of(context).colorScheme;

    return SearchBar(
      controller: _controller,
      hintText: widget.labelText ?? widget.hint,
      elevation: const WidgetStatePropertyAll(0),
      backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainer),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      leading: Icon(
        Icons.search_rounded,
        color: AppColors.textTertiaryFor(brightness),
      ),
      trailing: [
        if (widget.onChanged != null)
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Clear',
                    icon: Icon(
                      Icons.close_rounded,
                      color: AppColors.textSecondaryFor(brightness),
                      size: AppDimens.iconSmall,
                    ),
                    onPressed: () {
                      _controller.clear();
                      widget.onChanged?.call('');
                    },
                  ),
          ),
      ],
      onTap: widget.onTap,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      textInputAction: TextInputAction.search,
      hintStyle: WidgetStatePropertyAll(
        AppTextStyle.rowSubtitle.copyWith(
          color: AppColors.textTertiaryFor(brightness),
        ),
      ),
      textStyle: WidgetStatePropertyAll(
        AppTextStyle.rowTitle.copyWith(
          color: AppColors.textPrimaryFor(brightness),
          fontWeight: FontWeight.w500,
        ),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        ),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: AppDimens.space16),
      ),
      constraints: const BoxConstraints(minHeight: 52),
      autoFocus: widget.autofocus,
    );
  }
}