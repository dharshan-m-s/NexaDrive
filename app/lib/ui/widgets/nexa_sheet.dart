import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_motion.dart';
import '../../core/design/app_typography.dart';
import 'nexa_motion.dart';
import 'nexa_surface.dart';

/// Opens a Material 3 modal bottom sheet.
///
/// The sheet itself uses the theme's `bottomSheetTheme` (tonal surface, 28dp
/// top corners, elevation 3). Callers whose content is a menu wrap it in a
/// [NexaSheetBody] so it paints its own modal surface over the transparent
/// sheet background.
///
/// Entrance/exit uses [AppMotion.sheetAnimationStyle], a controlled near-critical
/// settle. Drag-to-dismiss and its velocity snap stay with the framework's
/// bottom-sheet recogniser; app-level reduce motion shortens the entrance but
/// leaves the essential content fully visible throughout.
Future<T?> showNexaSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool isDismissible = true,
  bool enableDrag = true,
  Color? barrierColor,
  double? maxHeight,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    barrierColor:
        barrierColor ?? AppColors.scrimFor(Theme.of(context).brightness),
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    sheetAnimationStyle: AppMotion.sheetAnimationStyle,
    constraints:
        maxHeight != null ? BoxConstraints(maxHeight: maxHeight) : null,
    builder: (context) => builder(context),
  );
}

/// Opens a sheet whose content owns its own layout — a form or multi-section
/// sheet that already provides its own [SafeArea], padding and scrolling — and
/// relies on the theme surface for its background (rounded top, drag handle).
///
/// Use this for self-contained bodies such as [FileShareSheet] or [FolderPicker].
/// Use [showNexaSheet] with a [NexaSheetBody] instead for menu/action sheets.
Future<T?> showNexaFormSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool isDismissible = true,
  bool enableDrag = true,
  Color? barrierColor,
  double? maxHeight,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    barrierColor:
        barrierColor ?? AppColors.scrimFor(Theme.of(context).brightness),
    sheetAnimationStyle: AppMotion.sheetAnimationStyle,
    constraints:
        maxHeight != null ? BoxConstraints(maxHeight: maxHeight) : null,
    builder: builder,
  );
}

/// Sheet header with title and optional subtitle.
class NexaSheetHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onClose;
  final IconData? icon;

  const NexaSheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onClose,
    this.icon,
  });

  IconData _iconForTitle(String value) {
    final normalized = value.toLowerCase();
    if (normalized.contains('share')) {
      return Icons.share_outlined;
    }
    if (normalized.contains('propert') || normalized.contains('detail')) {
      return Icons.info_outline_rounded;
    }
    if (normalized.contains('folder') ||
        normalized.contains('move') ||
        normalized.contains('copy')) {
      return Icons.folder_open_rounded;
    }
    if (normalized.contains('user') || normalized.contains('member')) {
      return Icons.person_outline_rounded;
    }
    if (normalized.contains('upload')) {
      return Icons.cloud_upload_rounded;
    }
    if (normalized.contains('download')) {
      return Icons.download_rounded;
    }
    if (normalized.contains('delete') || normalized.contains('trash')) {
      return Icons.delete_outline_rounded;
    }
    if (normalized.contains('rename') || normalized.contains('edit')) {
      return Icons.edit_rounded;
    }
    return Icons.tune_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasTrailing = trailing != null || onClose != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageMargin,
        AppDimens.space16,
        AppDimens.pageMargin,
        AppDimens.space8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: AppDimens.touchTarget,
            height: AppDimens.touchTarget,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppDimens.radiusSmall),
            ),
            child: Icon(
              icon ?? _iconForTitle(title),
              size: AppDimens.iconMedium,
              color: scheme.onPrimaryContainer,
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
                  style: AppTextStyle.titleMedium.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: AppDimens.space4),
                  Text(
                    subtitle!,
                    style: AppTextStyle.bodySmall.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (hasTrailing) ...[
            const SizedBox(width: AppDimens.space12),
            trailing ??
                NexaElasticPress(
                  child: IconButton(
                    onPressed: onClose ?? () => Navigator.pop(context),
                    icon: Icon(
                      Icons.close_rounded,
                      size: AppDimens.iconMedium,
                      color: scheme.onSurfaceVariant,
                    ),
                    tooltip:
                        MaterialLocalizations.of(context).closeButtonTooltip,
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

/// Sheet content wrapper with a modal Material surface.
class NexaSheetBody extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const NexaSheetBody({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(
      AppDimens.pageMargin,
      0,
      AppDimens.pageMargin,
      AppDimens.space24,
    ),
  });

  @override
  Widget build(BuildContext context) {
    return NexaSurface(
      level: NexaSurfaceLevel.modal,
      radius: AppDimens.radiusSheet,
      child: Padding(
        // Keep text fields above the on-screen keyboard: stop the sheet's
        // scroll viewport where the keyboard begins.
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

/// Sheet action row — icon + label, rendered as a Material 3 list row.
class NexaSheetAction extends StatefulWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool destructive;
  final bool enabled;
  final Color? iconColor;
  final Color? backgroundColor;

  const NexaSheetAction({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.destructive = false,
    this.enabled = true,
    this.iconColor,
    this.backgroundColor,
  });

  @override
  State<NexaSheetAction> createState() => _NexaSheetActionState();
}

class _NexaSheetActionState extends State<NexaSheetAction> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = widget.destructive
        ? scheme.error
        : (widget.iconColor ?? scheme.primary);
    final bg = widget.backgroundColor ??
        (widget.destructive
            ? scheme.errorContainer
            : scheme.surfaceContainerHigh);

    // Full-width rows keep their geometry; a tonal press state carries the
    // feedback instead of shrinking the row and exposing the sheet behind it.
    return NexaElasticPress(
      enabled: widget.enabled,
      scale: false,
      tintColor: scheme.onSurface.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
      child: ListTile(
        enabled: widget.enabled,
        onTap: widget.enabled ? widget.onTap : null,
        leading: Container(
          width: AppDimens.iconTileLarge,
          height: AppDimens.iconTileLarge,
          decoration: BoxDecoration(
            color: widget.enabled ? bg : bg.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppDimens.radiusSmall),
          ),
          child: Icon(
            widget.icon,
            color:
                widget.enabled ? fg : scheme.onSurface.withValues(alpha: 0.38),
            size: AppDimens.iconMedium,
          ),
        ),
        title: Text(
          widget.title,
          style: AppTextStyle.titleSmall.copyWith(color: scheme.onSurface),
        ),
        subtitle: widget.subtitle == null
            ? null
            : Text(
                widget.subtitle!,
                style: AppTextStyle.bodySmall.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
        trailing: widget.onTap != null && !widget.destructive
            ? Icon(
                Icons.chevron_right_rounded,
                size: AppDimens.iconMedium,
                color: scheme.onSurfaceVariant,
              )
            : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
        ),
        minTileHeight: AppDimens.listHeight,
      ),
    );
  }
}

/// Action sheet (share sheet style) — full width buttons.
Future<T?> showNexaActionSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
  String? message,
}) {
  return showNexaSheet<T>(
    context,
    isScrollControlled: false,
    builder: (context) => _ActionSheetWrapper(
      title: title,
      message: message,
      child: builder(context),
    ),
  );
}

class _ActionSheetWrapper extends StatelessWidget {
  final String? title;
  final String? message;
  final Widget child;

  const _ActionSheetWrapper({
    required this.title,
    required this.message,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Drag handle — the Material bottom-sheet grabber.
        Container(
          width: AppDimens.space32,
          height: AppDimens.space4,
          margin: const EdgeInsets.only(top: AppDimens.space12),
          decoration: BoxDecoration(
            color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(AppDimens.radiusExtraSmall),
          ),
        ),
        if (title != null || message != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.pageMargin,
              AppDimens.space16,
              AppDimens.pageMargin,
              AppDimens.space8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Text(
                    title!,
                    style: AppTextStyle.titleMedium.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                if (message != null) ...[
                  const SizedBox(height: AppDimens.space4),
                  Text(
                    message!,
                    style: AppTextStyle.bodySmall.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        Flexible(child: child),
        const SizedBox(height: AppDimens.space8),
      ],
    );
  }
}

/// Material 3 confirmation dialog.
Future<bool?> showNexaConfirmation({
  required BuildContext context,
  required String title,
  required String message,
  String confirmText = 'Confirm',
  String cancelText = 'Cancel',
  bool isDestructive = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => NexaConfirmationDialog(
      title: title,
      message: message,
      confirmText: confirmText,
      cancelText: cancelText,
      isDestructive: isDestructive,
    ),
  );
}

class NexaConfirmationDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmText;
  final String cancelText;
  final bool isDestructive;
  final IconData? icon;

  const NexaConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmText,
    required this.cancelText,
    this.isDestructive = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final container =
        isDestructive ? scheme.errorContainer : scheme.primaryContainer;
    final onContainer =
        isDestructive ? scheme.onErrorContainer : scheme.onPrimaryContainer;

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusDialog),
      ),
      title: Row(
        children: [
          Container(
            width: AppDimens.touchTarget,
            height: AppDimens.touchTarget,
            decoration: BoxDecoration(
              color: container,
              borderRadius: BorderRadius.circular(AppDimens.radiusSmall),
            ),
            child: Icon(
              icon ??
                  (isDestructive
                      ? Icons.delete_outline_rounded
                      : Icons.help_outline_rounded),
              color: onContainer,
              size: AppDimens.iconMedium,
            ),
          ),
          const SizedBox(width: AppDimens.space12),
          Expanded(
            child: Text(
              title,
              style: AppTextStyle.titleMedium.copyWith(color: scheme.onSurface),
            ),
          ),
        ],
      ),
      content: Text(
        message,
        style: AppTextStyle.bodyMedium.copyWith(color: scheme.onSurfaceVariant),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppDimens.space16,
        0,
        AppDimens.space16,
        AppDimens.space16,
      ),
      actionsAlignment: MainAxisAlignment.end,
      actions: [
        NexaElasticPress(
          child: TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: scheme.onSurfaceVariant,
            ),
            child: Text(cancelText, style: AppTextStyle.labelLarge),
          ),
        ),
        const SizedBox(width: AppDimens.space8),
        NexaElasticPress(
          child: FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: isDestructive ? scheme.error : scheme.primary,
              foregroundColor:
                  isDestructive ? scheme.onError : scheme.onPrimary,
            ),
            child: Text(confirmText, style: AppTextStyle.labelLarge),
          ),
        ),
      ],
    );
  }
}
