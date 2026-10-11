import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';

/// Primary filled button — most prominent action.
class NexaFilledButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final bool isLoading;
  final bool fullWidth;
  final EdgeInsetsGeometry? padding;

  const NexaFilledButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
    this.isLoading = false,
    this.fullWidth = false,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final accent = AppColors.accentFor(brightness);
    final onPrimary =
        brightness == Brightness.dark ? Colors.black : Colors.white;

    Widget buttonChild = isLoading
        ? SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: onPrimary,
            ),
          )
        : (icon != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  icon!,
                  const SizedBox(width: AppDimens.space8),
                  child,
                ],
              )
            : child);

    final button = FilledButton(
      onPressed: isLoading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: onPrimary,
        disabledBackgroundColor: accent.withValues(alpha: 0.4),
        disabledForegroundColor: onPrimary.withValues(alpha: 0.6),
        minimumSize:
            Size(fullWidth ? double.infinity : 64, AppDimens.touchTargetLarge),
        padding: padding ??
            const EdgeInsets.symmetric(
              horizontal: AppDimens.space24,
              vertical: AppDimens.space12,
            ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        ),
        textStyle: AppTextStyle.button,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: buttonChild,
    );

    return fullWidth ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Secondary outlined button.
class NexaOutlinedButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final bool fullWidth;
  final Color? borderColor;
  final Color? foregroundColor;
  final EdgeInsetsGeometry? padding;

  const NexaOutlinedButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
    this.fullWidth = false,
    this.borderColor,
    this.foregroundColor,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final accent = AppColors.accentFor(brightness);
    final fg = foregroundColor ?? accent;

    Widget buttonChild = icon != null
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon!,
              const SizedBox(width: AppDimens.space8),
              child,
            ],
          )
        : child;

    final button = OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: fg,
        side: BorderSide(color: borderColor ?? accent, width: 1.5),
        minimumSize:
            Size(fullWidth ? double.infinity : 64, AppDimens.touchTargetLarge),
        padding: padding ??
            const EdgeInsets.symmetric(
              horizontal: AppDimens.space24,
              vertical: AppDimens.space12,
            ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        ),
        textStyle: AppTextStyle.button,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: buttonChild,
    );

    return fullWidth ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Tertiary text button.
class NexaTextButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final Color? foregroundColor;
  final EdgeInsetsGeometry? padding;

  const NexaTextButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
    this.foregroundColor,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final fg = foregroundColor ?? AppColors.accentFor(brightness);

    Widget buttonChild = icon != null
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon!,
              const SizedBox(width: AppDimens.space8),
              child,
            ],
          )
        : child;

    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: fg,
        padding: padding ??
            const EdgeInsets.symmetric(
              horizontal: AppDimens.space16,
              vertical: AppDimens.space8,
            ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        ),
        textStyle: AppTextStyle.buttonSmall,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: buttonChild,
    );
  }
}

/// Destructive filled button (red).
class NexaDestructiveButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final bool isLoading;
  final bool fullWidth;

  const NexaDestructiveButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.isLoading = false,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final error = AppColors.errorFor(brightness);

    return FilledButton(
      onPressed: isLoading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: error,
        foregroundColor: Colors.white,
        disabledBackgroundColor: error.withValues(alpha: 0.4),
        disabledForegroundColor: Colors.white.withValues(alpha: 0.6),
        minimumSize:
            Size(fullWidth ? double.infinity : 64, AppDimens.touchTargetLarge),
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.space24,
          vertical: AppDimens.space12,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        ),
        textStyle: AppTextStyle.button,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: isLoading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
          : child,
    );
  }
}

/// Icon button with proper touch target.
class NexaIconButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String? tooltip;
  final Color? color;
  final Color? backgroundColor;
  final double size;
  final bool isSelected;

  const NexaIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.color,
    this.backgroundColor,
    this.size = AppDimens.iconMedium,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final fg = color ?? AppColors.labelPrimaryFor(brightness);
    final bg = backgroundColor ??
        (isSelected
            ? AppColors.accentContainerFor(brightness)
            : Colors.transparent);

    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: size, color: fg),
      style: IconButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        minimumSize: const Size(AppDimens.touchTarget, AppDimens.touchTarget),
        padding: const EdgeInsets.all(AppDimens.space8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
        ),
      ),
    );
  }
}

/// Standard back affordance for a pushed NexaDrive page.
///
/// Uses `maybePop` so it is safe on a root route, and pulls its label from
/// `MaterialLocalizations` so it is localised rather than hard-coded "Back".
class NexaBackButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;

  const NexaBackButton({
    super.key,
    this.onPressed,
    this.icon = Icons.arrow_back_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return IconButton(
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
      icon: Icon(icon, color: AppColors.labelPrimaryFor(brightness)),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(
        minWidth: AppDimens.touchTarget,
        minHeight: AppDimens.touchTarget,
      ),
    );
  }
}

/// Filled icon button (for primary actions in toolbars).
class NexaFilledIconButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String? tooltip;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const NexaFilledIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final bg = backgroundColor ?? AppColors.accentFor(brightness);
    final fg = foregroundColor ??
        (brightness == Brightness.dark ? Colors.black : Colors.white);

    return IconButton.filled(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: AppDimens.iconMedium, color: fg),
      style: IconButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        minimumSize: const Size(AppDimens.touchTarget, AppDimens.touchTarget),
        padding: const EdgeInsets.all(AppDimens.space10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
        ),
      ),
    );
  }
}

/// Segmented control (iOS-style).
class NexaSegmentedControl<T> extends StatelessWidget {
  final Map<T, Widget> children;
  final T selected;
  final ValueChanged<T> onChanged;
  final Color? selectedColor;
  final Color? unselectedColor;

  const NexaSegmentedControl({
    super.key,
    required this.children,
    required this.selected,
    required this.onChanged,
    this.selectedColor,
    this.unselectedColor,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final onAccent = AppColors.onAccentContainerFor(brightness);
    final secondary = AppColors.labelSecondaryFor(brightness);

    return SegmentedButton<T>(
      segments: children.entries.map((entry) {
        return ButtonSegment<T>(
          value: entry.key,
          label: entry.value,
          icon: entry.value is! Icon ? null : entry.value as Icon?,
        );
      }).toList(),
      selected: {selected},
      onSelectionChanged: (Set<T> newSelection) {
        onChanged(newSelection.first);
      },
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return selectedColor ?? AppColors.accentContainerFor(brightness);
          }
          return Colors.transparent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return onAccent;
          }
          return unselectedColor ?? secondary;
        }),
        side: WidgetStatePropertyAll(
          BorderSide(color: AppColors.separatorOpaqueFor(brightness)),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusPill),
          ),
        ),
        textStyle: const WidgetStatePropertyAll(AppTextStyle.caption1),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(
              horizontal: AppDimens.space16, vertical: AppDimens.space8),
        ),
      ),
      showSelectedIcon: false,
    );
  }
}
