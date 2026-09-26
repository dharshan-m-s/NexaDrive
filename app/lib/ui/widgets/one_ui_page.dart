import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';

/// The single One UI page shell for NexaDrive.
///
/// One standard skeleton for every screen, so spacing, alignment and safe-area
/// handling are decided once instead of per screen:
///
///  * a **viewing area** — large page title, optional subtitle, optional
///    trailing action and optional leading control (back);
///  * a **body** that is either scrollable or pinned, constrained to a
///    readable width on large screens;
///  * an optional **bottom action bar** that stays clear of the system insets.
///
/// Two properties are load-bearing:
///
///  * The whole page sits inside a `Material`. Without one, `MaterialApp`
///    falls back to its diagnostic `_errorTextStyle` (monospace, 48px, a
///    *double* underline in pure yellow) as the ambient `DefaultTextStyle`, and
///    any `Text` that does not set `decoration` itself inherits it. Routed
///    pages without a `Scaffold` hit this in release builds. A transparent
///    `Material` installs the real text style and paints no background.
///  * Insets are applied here, once. Hand-rolled `Scaffold`s were the main
///    source of headers drifting under the status bar.
class OneUiPage extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? headerAction;

  /// Leading control in the viewing area, normally a back button. When null
  /// the title spans the full width.
  final Widget? leading;

  /// Trailing control pinned to the bottom of the page, above the system
  /// insets. Use for a primary action that must stay reachable.
  final Widget? bottomBar;

  final Widget body;

  /// When false the viewing area is omitted and [body] fills the page. Use for
  /// immersive surfaces (viewers, camera) that provide their own chrome.
  final bool showHeader;

  final bool scrollable;
  final EdgeInsetsGeometry padding;
  final Alignment alignment;

  /// Readable width ceiling. Null means unbounded (phones); pass
  /// [AppDimens.contentMaxWidth] for prose or form content on large screens.
  final double? maxWidth;

  /// Forces the header's title, subtitle and leading colour.
  ///
  /// Null derives them from the theme, which is right for every page on the
  /// app surface. Immersive pages that paint their own dark canvas (the video
  /// player, the scanner) must pass a light colour, since the theme's dark
  /// text would be invisible on black.
  final Color? headerForeground;

  const OneUiPage({
    super.key,
    required this.title,
    this.subtitle,
    this.headerAction,
    this.leading,
    this.bottomBar,
    required this.body,
    this.showHeader = true,
    this.scrollable = false,
    this.padding = const EdgeInsets.fromLTRB(
      AppDimens.pageMargin,
      0,
      AppDimens.pageMargin,
      AppDimens.space24,
    ),
    this.alignment = Alignment.topLeft,
    this.maxWidth,
    this.headerForeground,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeader)
            _ViewingArea(
              title: title,
              subtitle: subtitle,
              action: headerAction,
              leading: leading,
              foreground: headerForeground,
            ),
          Expanded(
            child: scrollable
                ? SingleChildScrollView(
                    padding: padding,
                    child: Align(
                      alignment: alignment,
                      child: _constrain(body),
                    ),
                  )
                : Padding(
                    padding: padding,
                    child: _constrain(body),
                  ),
          ),
          if (bottomBar != null) _BottomBar(bottomBar: bottomBar!),
        ],
      ),
    );
  }

  Widget _constrain(Widget child) => maxWidth == null
      ? child
      : Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth!),
            child: child,
          ),
        );
}

/// The upper "viewing area": leading control, title, context, trailing action.
class _ViewingArea extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? action;
  final Widget? leading;
  final Color? foreground;

  const _ViewingArea({
    required this.title,
    this.subtitle,
    this.action,
    this.leading,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final titleColor = foreground ?? AppColors.textPrimaryFor(brightness);
    final subtitleColor = foreground ?? AppColors.textSecondaryFor(brightness);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageMargin,
        AppDimens.space24,
        AppDimens.pageMargin,
        AppDimens.space12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: AppDimens.space8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyle.pageTitle.copyWith(color: titleColor),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: AppDimens.space4),
                  Text(
                    subtitle!,
                    style:
                        AppTextStyle.rowSubtitle.copyWith(color: subtitleColor),
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

/// Persistent bottom action area, held off the system inset.
class _BottomBar extends StatelessWidget {
  final Widget bottomBar;

  const _BottomBar({required this.bottomBar});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        AppDimens.pageMargin,
        AppDimens.space12,
        AppDimens.pageMargin,
        AppDimens.space12 + bottomInset,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: AppColors.dividerFor(Theme.of(context).brightness),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(top: false, child: bottomBar),
    );
  }
}

/// A horizontally padded column that keeps content on the page gutter.
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
              constraints:
                  const BoxConstraints(maxWidth: AppDimens.contentMaxWidth),
              child: child,
            ),
          );
    return Padding(padding: padding, child: content);
  }
}
