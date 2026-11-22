import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_motion.dart';
import '../../core/design/app_typography.dart';
import 'nexa_scroll_aware_header.dart';

/// Measures the actual large-title header height from the live text scale and
/// viewport. A fixed estimate left a dead band under short titles (Photos) and
/// clipped wrapped ones on narrow screens.
double nexaHeaderContentExtent(
  BuildContext context, {
  required String title,
  required String? subtitle,
  required Widget? leading,
  required Widget? action,
  required List<Widget>? actions,
  required bool largeTitle,
  double? trailingExtent,
  TextStyle? titleStyle,
  int titleMaxLines = 2,
  int subtitleMaxLines = 2,
  double? textWidth,
  double? topPadding,
  double? bottomPadding,
}) {
  final textScaler = MediaQuery.textScalerOf(context);
  final direction = Directionality.of(context);
  final trailingCount = (action == null ? 0 : 1) + (actions?.length ?? 0);
  final trailing = trailingExtent ??
      (trailingCount == 0
          ? 0.0
          : trailingCount * (AppDimens.touchTarget + AppDimens.space8));
  final leadingExtent =
      leading == null ? 0.0 : AppDimens.touchTarget + AppDimens.space8;
  final availableWidth = textWidth ??
      (MediaQuery.sizeOf(context).width -
          AppDimens.pageMargin * 2 -
          leadingExtent -
          (leading == null ? 0.0 : AppDimens.space16) -
          trailing);
  final lineWidth = availableWidth.clamp(48.0, double.infinity);

  double lineHeight(String value, TextStyle style, int maxLines) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      maxLines: maxLines,
      ellipsis: '…',
      textDirection: direction,
      textScaler: textScaler,
    )..layout(maxWidth: lineWidth);
    return painter.height;
  }

  final titleHeight = lineHeight(
    title,
    titleStyle ??
        (largeTitle ? AppTextStyle.headlineSmall : AppTextStyle.title2),
    titleMaxLines,
  );
  var textHeight = titleHeight;
  final sub = subtitle;
  if (sub != null && sub.isNotEmpty) {
    textHeight += AppDimens.space2 +
        lineHeight(sub, AppTextStyle.bodySmall, subtitleMaxLines);
  }
  var rowHeight = AppDimens.touchTarget;
  if (textHeight > rowHeight) rowHeight = textHeight;
  return ((topPadding ?? AppDimens.space16) +
          leadingExtent +
          rowHeight +
          (bottomPadding ?? AppDimens.space16))
      .ceilToDouble();
}

/// The single NexaDrive page shell — Material 3 tonal scaffold with a
/// large-title header and optional bottom action bar.
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
  final Widget? body;

  /// Pages that already render slivers can supply them here. The floating
  /// header is added as the first sliver of the same scroll view, which keeps
  /// its hide/reveal geometry and the content in one coordinated layout.
  final List<Widget> Function(BuildContext context)? sliverBuilder;
  final RefreshCallback? onRefresh;
  final Widget? bottomBar;
  final EdgeInsetsGeometry padding;
  final double? maxWidth;

  /// Override the header's content extent when a screen knows its chrome is
  /// shorter than the shell's conservative default.
  final double? headerContentExtent;
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
    this.body,
    this.sliverBuilder,
    this.onRefresh,
    this.bottomBar,
    this.padding = const EdgeInsets.fromLTRB(
      AppDimens.pageMargin,
      0,
      AppDimens.pageMargin,
      0,
    ),
    this.maxWidth = AppDimens.contentMaxWidth,
    this.headerContentExtent,
    this.backgroundColor,
    this.headerForeground,
    this.headerIcon,
  });

  @override
  Widget build(BuildContext context) {
    assert(
      body != null || sliverBuilder != null,
      'NexaPage needs either body or sliverBuilder.',
    );
    final scheme = Theme.of(context).colorScheme;
    final bg = backgroundColor ?? scheme.surface;
    final fg = headerForeground ?? scheme.onSurface;
    final pagePadding = padding.resolve(Directionality.of(context));
    final viewPadding = MediaQuery.paddingOf(context);
    final topInset = viewPadding.top;
    final bottomClearance = viewPadding.bottom;
    final scrollPadding = bottomSafeArea
        ? pagePadding
        : pagePadding.copyWith(
            bottom: pagePadding.bottom > bottomClearance
                ? pagePadding.bottom
                : bottomClearance,
          );
    // Fixed extents keep the sliver's layout stable while it snaps. Screens
    // with known short chrome can override this through [headerContentExtent].
    final headerExtent = headerContentExtent ??
        (leading != null
            ? (largeTitle ? 184.0 : 192.0)
            : (largeTitle ? 128.0 : 136.0));

    Widget buildHeader() => NexaScrollAwareHeader(
          header: _Header(
            title: title,
            subtitle: subtitle,
            leading: leading,
            action: headerAction,
            actions: actions,
            largeTitle: largeTitle,
            foreground: fg,
            icon: headerIcon,
          ),
          backgroundColor: bg,
          initialContentExtent: headerExtent,
        );

    final Widget scrollView;
    if (sliverBuilder != null) {
      // Pages that own their content slivers share one scroll position with
      // the header. Nothing below changes size when the chrome snaps away.
      scrollView = NexaHeaderSnapScrollView(
        headerExtent: topInset + headerExtent,
        slivers: [
          buildHeader(),
          ...sliverBuilder!(context),
        ],
        onRefresh: onRefresh,
      );
    } else {
      // Generic pages keep the old body contract: the body receives bounded
      // height and may bring its own ListView/Expanded. NestedScrollView is the
      // framework's coordinator for a floating header above such a body, so
      // scrolling the inner list still drives the outer header.
      Widget content = _constrain(body!);
      content = scrollable
          ? SingleChildScrollView(padding: scrollPadding, child: content)
          : Padding(padding: pagePadding, child: content);
      scrollView = _NestedPageScrollView(
        headerExtent: topInset + headerExtent,
        headerBuilder: (_) => buildHeader(),
        body: onRefresh == null
            ? content
            : RefreshIndicator(onRefresh: onRefresh!, child: content),
      );
    }

    return SafeArea(
      top: false,
      bottom: bottomSafeArea,
      child: Material(
        type: MaterialType.transparency,
        child: DecoratedBox(
          decoration: BoxDecoration(color: bg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: scrollView),
              if (bottomBar != null)
                _BottomBar(
                  bottomBar: bottomBar!,
                  applyBottomInset: bottomSafeArea,
                ),
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

/// Coordinates a floating header with a body that owns its own scroll view.
///
/// NestedScrollView moves its outer header programmatically from inner scroll
/// events, so Flutter's built-in floating-header snap listener never sees a
/// scroll gesture on the outer position. This listens to the inner body and
/// performs the same settle once the gesture ends.
class _NestedPageScrollView extends StatefulWidget {
  const _NestedPageScrollView({
    required this.headerExtent,
    required this.headerBuilder,
    required this.body,
  });

  final double headerExtent;
  final Widget Function(BuildContext context) headerBuilder;
  final Widget body;

  @override
  State<_NestedPageScrollView> createState() => _NestedPageScrollViewState();
}

class _NestedPageScrollViewState extends State<_NestedPageScrollView> {
  final GlobalKey<NestedScrollViewState> _nestedKey =
      GlobalKey<NestedScrollViewState>();

  /// NestedScrollView mirrors outer settles onto the inner position. Those
  /// programmatic notifications are not new gestures and must not re-snap the
  /// header in the opposite direction.
  bool _settling = false;

  bool _onBodyNotification(ScrollNotification notification) {
    final outer = _nestedKey.currentState?.outerController;

    if (notification is ScrollStartNotification) {
      if (_settling && notification.dragDetails == null) return false;
      _settling = false;
      return false;
    }

    if (notification is ScrollEndNotification && outer?.hasClients == true) {
      if (_settling) {
        _settling = false;
        return false;
      }
      final hidden = outer!.position.maxScrollExtent;
      // NestedScrollView's inner body can stay at offset zero while its outer
      // header position follows the gesture. The outer position therefore owns
      // the authoritative direction at release; the inner direction can be idle
      // even after a long drag.
      final direction = outer.position.userScrollDirection;
      final target = direction == ScrollDirection.reverse ||
              (direction == ScrollDirection.idle &&
                  outer.position.pixels > hidden / 2)
          ? hidden
          : 0.0;
      if ((outer.position.pixels - target).abs() > 1) {
        _settling = true;
        final duration = AppMotion.resolve(context, AppMotion.headerSettle);
        // The outer position is driven programmatically by NestedScrollView;
        // defer one frame so the inner drag's final update cannot cancel this
        // settle.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final nested = _nestedKey.currentState;
          if (!mounted ||
              nested == null ||
              !nested.outerController.hasClients) {
            return;
          }
          nested.outerController.animateTo(
            target,
            duration: duration,
            curve: AppMotion.headerRevealCurve,
          );
        });
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NestedScrollView(
      key: _nestedKey,
      headerSliverBuilder: (context, _) => [widget.headerBuilder(context)],
      body: NotificationListener<ScrollNotification>(
        onNotification: _onBodyNotification,
        child: widget.body,
      ),
    );
  }
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
    final scheme = Theme.of(context).colorScheme;
    final titleStyle =
        (largeTitle ? AppTextStyle.headlineSmall : AppTextStyle.title2)
            .copyWith(color: foreground);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageMargin,
        AppDimens.space16,
        AppDimens.pageMargin,
        AppDimens.space16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        // The back affordance keeps its intrinsic size instead of being
        // stretched to the full header width, which used to centre the arrow.
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(height: AppDimens.space8),
          ],
          SizedBox(
            width: double.infinity,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: AppDimens.touchTarget,
                    height: AppDimens.touchTarget,
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius:
                          BorderRadius.circular(AppDimens.radiusMedium),
                    ),
                    child: Icon(
                      icon ?? _iconForTitle(title),
                      color: scheme.onSecondaryContainer,
                      size: AppDimens.iconMedium,
                    ),
                  ),
                ),
                const SizedBox(width: AppDimens.space16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: AppDimens.space2),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.bodySmall.copyWith(
                            color: scheme.onSurfaceVariant,
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
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final Widget bottomBar;
  final bool applyBottomInset;

  const _BottomBar({
    required this.bottomBar,
    required this.applyBottomInset,
  });

  @override
  Widget build(BuildContext context) {
    final child =
        applyBottomInset ? SafeArea(top: false, child: bottomBar) : bottomBar;
    return Container(
      width: double.infinity,
      // A full-bleed page already lets its bar publish its own pill clearance;
      // adding another SafeArea here produced a strip below the floating pill.
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageMargin,
        AppDimens.space8,
        AppDimens.pageMargin,
        AppDimens.space8,
      ),
      child: child,
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
    final bg = backgroundColor ?? Theme.of(context).colorScheme.surface;

    return Material(
      color: bg,
      child: Column(
        children: [
          Expanded(child: body),
          if (bottomBar != null)
            _BottomBar(bottomBar: bottomBar!, applyBottomInset: true),
        ],
      ),
    );
  }
}
