import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';
import 'nexa_surface.dart';
import 'nexa_chip.dart';
import 'nexa_list_tile.dart';

/// One UI-inspired grouped section for related settings and actions.
class NexaGroupedList extends StatelessWidget {
  final String? header;
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;
  final bool withDividers;
  final Widget? footer;

  const NexaGroupedList({
    super.key,
    this.header,
    required this.children,
    this.padding,
    this.withDividers = true,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final divider = AppColors.separatorOpaqueFor(brightness);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null) NexaSectionHeader(header!, padding: padding),
        NexaSurface(
          level: NexaSurfaceLevel.grouped,
          radius: AppDimens.radiusXLarge,
          padding:
              padding ?? const EdgeInsets.symmetric(vertical: AppDimens.space4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppDimens.radiusXLarge),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    children[i],
                    if (withDividers && i < children.length - 1)
                      Padding(
                        padding: EdgeInsets.only(
                          left: _insetFor(children[i]),
                          right: AppDimens.pageMargin,
                        ),
                        child: Divider(
                          color: divider,
                          height: 0.5,
                          thickness: 0.5,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (footer != null) ...[
          const SizedBox(height: AppDimens.space12),
          footer!,
        ],
        const SizedBox(height: AppDimens.space8),
      ],
    );
  }

  static double _insetFor(Widget child) {
    if (child is NexaListTile && child.leading != null) {
      return AppDimens.pageMargin + AppDimens.iconTileLarge + AppDimens.space12;
    }
    return AppDimens.pageMargin;
  }
}

/// Responsive page container with max content width.
class NexaPageContainer extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget? leading;
  final Widget? headerAction;
  final Widget? bottomBar;
  final Widget body;
  final bool showHeader;
  final bool scrollable;
  final EdgeInsetsGeometry padding;
  final AlignmentGeometry alignment;
  final double? maxWidth;
  final Color? headerForeground;

  const NexaPageContainer({
    super.key,
    this.title,
    this.subtitle,
    this.leading,
    this.headerAction,
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
    this.maxWidth = AppDimens.contentMaxWidth,
    this.headerForeground,
  });

  IconData _pageIcon(String value) {
    final title = value.toLowerCase();
    if (title.contains('file') || title.contains('folder')) return Icons.folder_copy_rounded;
    if (title.contains('photo')) return Icons.photo_library_rounded;
    if (title.contains('share')) return Icons.people_alt_rounded;
    if (title.contains('trash')) return Icons.delete_sweep_rounded;
    if (title.contains('sync')) return Icons.sync_rounded;
    if (title.contains('transfer')) return Icons.cloud_upload_rounded;
    if (title.contains('setting')) return Icons.tune_rounded;
    if (title.contains('notification')) return Icons.notifications_active_rounded;
    return Icons.cloud_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final edgeInsets = padding.resolve(Directionality.of(context));
    final effectivePadding =
        scrollable ? EdgeInsets.only(bottom: edgeInsets.bottom) : edgeInsets;
    final brightness = Theme.of(context).brightness;
    final headerForegroundColor =
        headerForeground ?? AppColors.labelPrimaryFor(brightness);

    final header = showHeader &&
            (title != null || leading != null || headerAction != null)
        ? Padding(
            padding: EdgeInsets.fromLTRB(
              edgeInsets.left,
              edgeInsets.top,
              edgeInsets.right,
              0,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (leading != null) leading!,
                if (leading != null) const SizedBox(width: AppDimens.space12),
                if (title != null)
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.accentContainerFor(brightness),
                      borderRadius: BorderRadius.circular(AppDimens.radiusMedium),
                      border: Border.all(
                        color: AppColors.accentTextFor(brightness).withValues(alpha: 0.12),
                      ),
                    ),
                    child: Icon(
                      _pageIcon(title!),
                      size: 21,
                      color: AppColors.accentTextFor(brightness),
                    ),
                  ),
                if (title != null) const SizedBox(width: AppDimens.space12),
                if (title != null || subtitle != null)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (title != null)
                          Text(
                            title!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyle.largeTitle.copyWith(
                              color: headerForegroundColor,
                              letterSpacing: -0.45,
                            ),
                          ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: AppTextStyle.caption1.copyWith(
                              color:
                                  headerForegroundColor.withValues(alpha: 0.7),
                            ),
                          ),
                      ],
                    ),
                  )
                else
                  const SizedBox.shrink(),
                if (headerAction != null) ...[
                  const SizedBox(width: AppDimens.space12),
                  headerAction!,
                ],
              ],
            ),
          )
        : const SizedBox.shrink();

    final bodyWidget = Padding(
      padding: EdgeInsets.only(
        left: edgeInsets.left,
        right: edgeInsets.right,
        bottom: edgeInsets.bottom,
        top: showHeader &&
                (title != null || leading != null || headerAction != null)
            ? 0
            : edgeInsets.top,
      ),
      child: body,
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader &&
            (title != null || leading != null || headerAction != null))
          header,
        Expanded(child: bodyWidget),
        if (bottomBar != null)
          Padding(
            padding: EdgeInsets.only(
              left: edgeInsets.left,
              right: edgeInsets.right,
              bottom: edgeInsets.bottom,
            ),
            child: bottomBar!,
          ),
      ],
    );

    final contentWidget = maxWidth == null
        ? content
        : Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth!),
              child: content,
            ),
          );

    final padded = Padding(padding: effectivePadding, child: contentWidget);

    if (!scrollable) return padded;
    return SingleChildScrollView(
      padding: EdgeInsets.zero,
      child: padded,
    );
  }
}
