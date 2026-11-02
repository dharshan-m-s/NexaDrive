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

  /// Whether this page should consume the device bottom safe area. The main
  /// tab pages disable it so their background extends behind the floating pill;
  /// standalone routes keep the default safe-area behavior.
  final bool bottomSafeArea;
  final Widget body;
  final Widget? bottomBar;
  final EdgeInsetsGeometry padding;
  final double? maxWidth;
  final Color? backgroundColor;
  final Color? headerForeground;
  final IconData? headerIcon;

  const NexaPage({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions,
    this.headerAction,
    this.largeTitle = true,
    this.scrollable = false,
    this.bottomSafeArea = true,
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
    this.headerIcon,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final bg = backgroundColor ?? AppColors.backgroundFor(brightness);
    final fg = headerForeground ?? AppColors.labelPrimaryFor(brightness);
    final pagePadding = padding.resolve(Directionality.of(context));
    final bottomClearance = MediaQuery.paddingOf(context).bottom;
    final scrollPadding = bottomSafeArea
        ? pagePadding
        : pagePadding.copyWith(
            bottom: pagePadding.bottom > bottomClearance
                ? pagePadding.bottom
                : bottomClearance,
          );

    return SafeArea(
      // Main tabs let the page continue behind the floating pill. Standalone
      // routes retain normal bottom-inset protection through the default flag.
      top: true,
      bottom: bottomSafeArea,
      child: Material(
        type: MaterialType.transparency,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bg,
          ),
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
                icon: headerIcon,
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
  final IconData? icon;

  const _Header({
    required this.title,
    this.subtitle,
    this.leading,
    this.action,
    this.actions,
    required this.largeTitle,
    required this.foreground,
    this.icon,
  });

  IconData _iconForTitle(String value) {
    final title = value.toLowerCase();
    if (title.contains('storage') || title.contains('insight')) {
      return Icons.donut_large_rounded;
    }
    if (title.contains('file') || title.contains('folder')) {
      return Icons.folder_copy_rounded;
    }
    if (title.contains('shared') || title.contains('collabor')) {
      return Icons.people_alt_rounded;
    }
    if (title.contains('photo') || title.contains('gallery')) {
      return Icons.photo_library_rounded;
    }
    if (title.contains('trash') || title.contains('recover')) {
      return Icons.delete_sweep_rounded;
    }
    if (title.contains('setting') || title.contains('preference')) {
      return Icons.tune_rounded;
    }
    if (title.contains('sync')) return Icons.sync_rounded;
    if (title.contains('notification')) {
      return Icons.notifications_active_rounded;
    }
    if (title.contains('transfer') ||
        title.contains('upload') ||
        title.contains('download')) {
      return Icons.cloud_upload_rounded;
    }
    if (title.contains('search')) return Icons.search_rounded;
    if (title.contains('scan')) return Icons.document_scanner_rounded;
    if (title.contains('security') || title.contains('lock')) {
      return Icons.shield_rounded;
    }
    if (title.contains('update')) return Icons.system_update_alt_rounded;
    if (title.contains('user') || title.contains('admin')) {
      return Icons.manage_accounts_rounded;
    }
    if (title.contains('audit') || title.contains('log')) {
      return Icons.fact_check_rounded;
    }
    if (title.contains('pdf')) return Icons.picture_as_pdf_rounded;
    if (title.contains('video')) return Icons.play_circle_rounded;
    if (title.contains('audio') || title.contains('music')) {
      return Icons.graphic_eq_rounded;
    }
    if (title.contains('text')) return Icons.article_rounded;
    return Icons.cloud_rounded;
  }

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
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.accentContainerFor(brightness),
                          borderRadius: BorderRadius.circular(AppDimens.radiusMedium),
                          border: Border.all(
                            color: AppColors.separatorFor(brightness)
                                .withValues(alpha: 0.72),
                            width: 0.7,
                          ),
                        ),
                        child: Icon(
                          icon ?? _iconForTitle(title),
                          color: AppColors.accentTextFor(brightness),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: AppDimens.space12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.largeTitle.copyWith(
                                color: foreground,
                                letterSpacing: -0.55,
                                height: 1.04,
                              ),
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: AppDimens.space2),
                              Text(
                                subtitle!,
                                style: AppTextStyle.caption1.copyWith(
                                  color: AppColors.labelSecondaryFor(
                                    brightness,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
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
