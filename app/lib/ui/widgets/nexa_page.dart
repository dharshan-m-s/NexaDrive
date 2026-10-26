import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';

/// The single NexaDrive page shell — iOS-style with large title support.
class NexaPage extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? headerAction;
  final List<Widget>? actions;
  final bool largeTitle;
  final bool scrollable;
  final Widget body;
  final Widget? bottomBar;
  final EdgeInsetsGeometry padding;
  final double? maxWidth;
  final Color? backgroundColor;
  final Color? headerForeground;

  const NexaPage({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions,
    this.headerAction,
    this.largeTitle = true,
    this.scrollable = false,
    required this.body,
    this.bottomBar,
    this.padding = const EdgeInsets.fromLTRB(
      AppDimens.pageMargin,
      0,
      AppDimens.pageMargin,
      0,
    ),
    this.maxWidth = AppDimens.contentMaxWidth,
    this.backgroundColor,
    this.headerForeground,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final bg = backgroundColor ?? AppColors.backgroundFor(brightness);
    final fg = headerForeground ?? AppColors.labelPrimaryFor(brightness);
    final pagePadding = padding.resolve(Directionality.of(context));
    final bottomClearance = MediaQuery.paddingOf(context).bottom;
    final scrollPadding = pagePadding.copyWith(
      bottom: pagePadding.bottom > bottomClearance
          ? pagePadding.bottom
          : bottomClearance,
    );

    return SafeArea(
      // The shell owns bottom navigation clearance. Do not consume that inset
      // here; scrollables need to see it to keep their final items reachable
      // above the floating pill while the page itself continues behind it.
      top: true,
      bottom: false,
      child: Material(
        type: MaterialType.transparency,
        child: ColoredBox(
          color: bg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header / Viewing Area
              _Header(
                title: title,
                subtitle: subtitle,
                leading: leading,
                action: headerAction,
                actions: actions,
                largeTitle: largeTitle,
                foreground: fg,
              ),
              // Body
              Expanded(
                child: scrollable
                    ? SingleChildScrollView(
                      padding: scrollPadding,
                      child: _constrain(body),
                    )
                    : Padding(
                      padding: padding,
                      child: _constrain(body),
                    ),
              ),
              // Bottom bar
              if (bottomBar != null) _BottomBar(bottomBar: bottomBar!),
            ],
          ),
        ),
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

class _Header extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget>? actions;
  final Widget? action;
  final bool largeTitle;
  final Color foreground;

  const _Header({
    required this.title,
    this.subtitle,
    this.leading,
    this.action,
    this.actions,
    required this.largeTitle,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    if (largeTitle) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pageMargin,
          AppDimens.space8,
          AppDimens.pageMargin,
          AppDimens.space8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(height: AppDimens.space8),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style:
                            AppTextStyle.largeTitle.copyWith(color: foreground),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: AppDimens.space2),
                        Text(
                          subtitle!,
                          style: AppTextStyle.caption1.copyWith(
                            color: AppColors.labelSecondaryFor(brightness),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(width: AppDimens.space8),
                  action!,
                ],
                if (actions != null) ...[
                  const SizedBox(width: AppDimens.space8),
                  ...actions!,
                ],
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageMargin,
        AppDimens.space8,
        AppDimens.pageMargin,
        AppDimens.space4,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: AppDimens.space8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTextStyle.pageTitle.copyWith(color: foreground),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: AppDimens.space2),
                  Text(
                    subtitle!,
                    style: AppTextStyle.caption1.copyWith(
                      color: AppColors.labelSecondaryFor(brightness),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (action != null) action!,
          if (actions != null) ...actions!,
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final Widget bottomBar;

  const _BottomBar({required this.bottomBar});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      // The child SafeArea supplies the system/host bottom inset exactly once.
      // Keep only visual spacing here to avoid doubling the inset.
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageMargin,
        AppDimens.space8,
        AppDimens.pageMargin,
        AppDimens.space8,
      ),
      child: SafeArea(top: false, child: bottomBar),
    );
  }
}

/// Body wrapper that constrains width on large screens.
class NexaPageBody extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? maxWidth;

  const NexaPageBody({
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
              constraints: BoxConstraints(maxWidth: maxWidth!),
              child: child,
            ),
          );
    return Padding(padding: padding, child: content);
  }
}

/// Immersive page (for viewers, camera, etc.) — no header.
class NexaImmersivePage extends StatelessWidget {
  final Widget body;
  final Widget? bottomBar;
  final Color? backgroundColor;

  const NexaImmersivePage({
    super.key,
    required this.body,
    this.bottomBar,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final bg = backgroundColor ?? AppColors.backgroundFor(brightness);

    return Material(
      color: bg,
      child: Column(
        children: [
          Expanded(child: body),
          if (bottomBar != null) _BottomBar(bottomBar: bottomBar!),
        ],
      ),
    );
  }
}
