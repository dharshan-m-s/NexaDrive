import 'package:flutter/material.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';

/// Primary filled button — most prominent action.
///
/// Renders Flutter's Material 3 [FilledButton], themed by [AppTheme] with the
/// seeded primary role, full shape and a 48dp touch target.
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
    final scheme = Theme.of(context).colorScheme;

    Widget buttonChild = isLoading
        ? SizedBox(
            width: AppDimens.iconSmall,
            height: AppDimens.iconSmall,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.onPrimary,
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
        minimumSize:
            Size(fullWidth ? double.infinity : 64, AppDimens.touchTarget),
        padding: padding ??
            const EdgeInsets.symmetric(horizontal: AppDimens.space24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
        ),
        textStyle: AppTextStyle.labelLarge,
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
    final scheme = Theme.of(context).colorScheme;

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
        foregroundColor: foregroundColor ?? scheme.primary,
        side: BorderSide(color: borderColor ?? scheme.outline, width: 1),
        minimumSize:
            Size(fullWidth ? double.infinity : 64, AppDimens.touchTarget),
        padding: padding ??
            const EdgeInsets.symmetric(horizontal: AppDimens.space24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
        ),
        textStyle: AppTextStyle.labelLarge,
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
    final scheme = Theme.of(context).colorScheme;

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
        foregroundColor: foregroundColor ?? scheme.primary,
        padding: padding ??
            const EdgeInsets.symmetric(
              horizontal: AppDimens.space16,
              vertical: AppDimens.space8,
            ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusSmall),
        ),
        textStyle: AppTextStyle.labelLarge,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: buttonChild,
    );
  }
}

/// Destructive filled button (Material error role).
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
    final scheme = Theme.of(context).colorScheme;

    final button = FilledButton(
      onPressed: isLoading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: scheme.error,
        foregroundColor: scheme.onError,
        minimumSize: Size(
          fullWidth ? double.infinity : 64,
          AppDimens.touchTarget,
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppDimens.space24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
        ),
        textStyle: AppTextStyle.labelLarge,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: isLoading
          ? SizedBox(
              width: AppDimens.iconSmall,
              height: AppDimens.iconSmall,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.onError,
              ),
            )
          : child,
    );

    return fullWidth ? SizedBox(width: double.infinity, child: button) : button;
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
    final scheme = Theme.of(context).colorScheme;
    final fg = color ?? scheme.onSurfaceVariant;
    final bg = backgroundColor ??
        (isSelected ? scheme.secondaryContainer : Colors.transparent);

    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: size, color: fg),
      style: IconButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        minimumSize: const Size(AppDimens.touchTarget, AppDimens.touchTarget),
        padding: const EdgeInsets.all(AppDimens.space8),
        shape: const StadiumBorder(),
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
    final scheme = Theme.of(context).colorScheme;

    return IconButton(
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
      icon: Icon(icon, color: scheme.onSurface),
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
    final scheme = Theme.of(context).colorScheme;
    final bg = backgroundColor ?? scheme.primary;
    final fg = foregroundColor ?? scheme.onPrimary;

    return IconButton.filled(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: AppDimens.iconMedium, color: fg),
      style: IconButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        minimumSize: const Size(AppDimens.touchTarget, AppDimens.touchTarget),
        padding: const EdgeInsets.all(AppDimens.space8),
        shape: const StadiumBorder(),
      ),
    );
  }
}

/// Material 3 segmented button, themed with the seeded secondary container.
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
    final scheme = Theme.of(context).colorScheme;

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
            return selectedColor ?? scheme.secondaryContainer;
          }
          return Colors.transparent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.onSecondaryContainer;
          }
          return unselectedColor ?? scheme.onSurfaceVariant;
        }),
        side:
            WidgetStatePropertyAll(BorderSide(color: scheme.outline, width: 1)),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        minimumSize: const WidgetStatePropertyAll(
          Size(64, AppDimens.touchTarget),
        ),
        textStyle: const WidgetStatePropertyAll(AppTextStyle.labelLarge),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(
            horizontal: AppDimens.space16,
            vertical: AppDimens.space8,
          ),
        ),
      ),
      showSelectedIcon: false,
    );
  }
}
