import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_motion.dart';
import '../../core/design/app_typography.dart';

/// Opens an iOS-style modal bottom sheet.
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
/// Use [showNexaSheet] with a [NexaSheetBody] instead for menu/action sheets:
/// [NexaSheetBody] paints its own opaque elevated surface, separate from the
/// floating navigation dock and from the page beneath it. A self-contained
/// body such as [FolderPickerBody] should use [showNexaFormSheet] instead.
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

  const NexaSheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyle.sectionHeader.copyWith(
                    color: AppColors.labelPrimaryFor(brightness),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: AppDimens.space4),
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
          if (hasTrailing) ...[
            const SizedBox(width: AppDimens.space12),
            trailing ??
                IconButton(
                  onPressed: onClose ?? () => Navigator.pop(context),
                  icon: Icon(
                    Icons.close_rounded,
                    size: AppDimens.iconMedium,
                    color: AppColors.labelSecondaryFor(brightness),
                  ),
                  tooltip: 'Close',
                ),
          ],
        ],
      ),
    );
  }
}

/// Sheet content wrapper with proper styling.
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
    final brightness = Theme.of(context).brightness;

    return Material(
      color: AppColors.surfaceElevatedFor(brightness),
      elevation: 22,
      shadowColor: Colors.black.withValues(alpha: 0.28),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppDimens.radiusXLarge),
        ),
        side: BorderSide(
          color: AppColors.separatorOpaqueFor(brightness),
          width: 0.7,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.zero,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(
                    top: AppDimens.space12,
                    bottom: AppDimens.space12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.separatorOpaqueFor(brightness),
                    borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                  ),
                ),
                Padding(padding: padding, child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sheet action row — icon + label.
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
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDestructive = widget.destructive;
    final fg = isDestructive
        ? AppColors.errorFor(brightness)
        : (widget.iconColor ?? AppColors.labelPrimaryFor(brightness));
    final bg = widget.backgroundColor ??
        (isDestructive
            ? AppColors.errorContainerFor(brightness)
            : AppColors.fillFor(brightness));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.enabled ? widget.onTap : null,
        onHover: (hovered) {
          if (widget.enabled && _hovered != hovered) {
            setState(() => _hovered = hovered);
          }
        },
        borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
        child: AnimatedContainer(
          duration: AppMotion.resolve(context, AppMotion.fast),
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.space16,
            vertical: AppDimens.space12,
          ),
          decoration: BoxDecoration(
            color: widget.enabled && _hovered
                ? AppColors.fillFor(brightness).withValues(alpha: 0.58)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
          ),
          child: Row(
            children: [
              AnimatedScale(
                scale: _hovered && widget.enabled ? 1.035 : 1,
                duration: AppMotion.resolve(context, AppMotion.fast),
                child: Container(
                  width: AppDimens.iconTileLarge,
                  height: AppDimens.iconTileLarge,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(
                      AppDimens.radiusStandard,
                    ),
                  ),
                  child: Icon(
                    widget.icon,
                    color: widget.enabled
                        ? fg
                        : AppColors.labelTertiaryFor(brightness),
                    size: AppDimens.iconMedium,
                  ),
                ),
              ),
              const SizedBox(width: AppDimens.space16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: AppTextStyle.rowTitle.copyWith(
                        color: widget.enabled
                            ? AppColors.labelPrimaryFor(brightness)
                            : AppColors.labelTertiaryFor(brightness),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: AppDimens.space2),
                      Text(
                        widget.subtitle!,
                        style: AppTextStyle.caption1.copyWith(
                          color: AppColors.labelSecondaryFor(brightness),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.onTap != null && !isDestructive)
                Icon(
                  Icons.chevron_right_rounded,
                  size: AppDimens.iconMedium,
                  color: AppColors.labelTertiaryFor(brightness),
                ),
            ],
          ),
        ),
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
    final brightness = Theme.of(context).brightness;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Drag handle
        Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.only(top: AppDimens.space12),
          decoration: BoxDecoration(
            color: AppColors.separatorOpaqueFor(brightness),
            borderRadius: BorderRadius.circular(2),
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
                    style: AppTextStyle.sectionHeader.copyWith(
                      color: AppColors.labelPrimaryFor(brightness),
                    ),
                  ),
                if (message != null) ...[
                  const SizedBox(height: AppDimens.space4),
                  Text(
                    message!,
                    style: AppTextStyle.caption1.copyWith(
                      color: AppColors.labelSecondaryFor(brightness),
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

/// Confirmation dialog (iOS-style alert).
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

  const NexaConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmText,
    required this.cancelText,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final confirmColor = isDestructive
        ? AppColors.errorFor(brightness)
        : AppColors.accentFor(brightness);

    return AlertDialog(
      backgroundColor: AppColors.surfaceFor(brightness),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusXLarge),
      ),
      title: Text(
        title,
        style: AppTextStyle.sectionHeader.copyWith(
          color: AppColors.labelPrimaryFor(brightness),
        ),
      ),
      content: Text(
        message,
        style: AppTextStyle.body.copyWith(
          color: AppColors.labelSecondaryFor(brightness),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppDimens.space16,
        0,
        AppDimens.space16,
        AppDimens.space16,
      ),
      actionsAlignment: MainAxisAlignment.end,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.labelSecondaryFor(brightness),
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.space24,
              vertical: AppDimens.space12,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDimens.radiusPill),
            ),
          ),
          child: Text(cancelText, style: AppTextStyle.buttonSmall),
        ),
        const SizedBox(width: AppDimens.space8),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(
            backgroundColor: confirmColor,
            foregroundColor: isDestructive
                ? Colors.white
                : (brightness == Brightness.dark ? Colors.black : Colors.white),
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.space24,
              vertical: AppDimens.space12,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDimens.radiusPill),
            ),
          ),
          child: Text(confirmText, style: AppTextStyle.buttonSmall),
        ),
      ],
    );
  }
}
