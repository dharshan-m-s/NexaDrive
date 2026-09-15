import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';

/// Standard One UI screen skeleton.
///
/// Top region: large page title + optional subtitle/context + optional
/// action controls. Body below with comfortable horizontal margins.
/// Interaction controls belong in the lower area, not the top.
class OneUiPage extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? headerAction;
  final Widget body;
  final bool scrollable;
  final EdgeInsetsGeometry padding;
  final Alignment alignment;

  const OneUiPage({
    super.key,
    required this.title,
    this.subtitle,
    this.headerAction,
    required this.body,
    this.scrollable = false,
    this.padding = const EdgeInsets.fromLTRB(
      AppDimens.pageMargin, 0, AppDimens.pageMargin, AppDimens.space24,
    ),
    this.alignment = Alignment.topLeft,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ViewingArea(
          title: title,
          subtitle: subtitle,
          action: headerAction,
        ),
        Expanded(
          child: scrollable
              ? SingleChildScrollView(
                  padding: padding,
                  child: Align(alignment: alignment, child: body),
                )
              : Padding(padding: padding, child: body),
        ),
      ],
    );
  }
}

/// The upper "viewing area": title + context.
class _ViewingArea extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? action;

  const _ViewingArea({required this.title, this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageMargin, AppDimens.space24, AppDimens.pageMargin, AppDimens.space12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyle.pageTitle
                      .copyWith(color: AppColors.textPrimaryFor(brightness)),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: AppDimens.space4),
                  Text(
                    subtitle!,
                    style: AppTextStyle.rowSubtitle
                        .copyWith(color: AppColors.textSecondaryFor(brightness)),
                  ),
                ],
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: AppDimens.space12),
            action!,
          ],
        ],
      ),
    );
  }
}

/// A horizontally-padded column that keeps content on the page gutter.
class OneUiBody extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? maxWidth;

  const OneUiBody({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: AppDimens.pageMargin),
    this.maxWidth = AppDimens.contentMaxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final content = maxWidth == null
        ? child
        : Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppDimens.contentMaxWidth),
              child: child,
            ),
          );
    return Padding(padding: padding, child: content);
  }
}