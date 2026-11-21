import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_dimensions.dart';
import 'app_typography.dart';
import 'app_transitions.dart';

/// NexaDrive theme — warm editorial Material 3.
///
/// Material roles still drive every component, but the roles are tuned to the
/// ivory/forest palette. Surfaces are solid, dividers are hairlines and shape
/// stays restrained; the floating pill is the only capsule in the system.
abstract final class AppTheme {
  static ThemeData light({bool highContrast = false}) =>
      _build(Brightness.light, highContrast);
  static ThemeData dark({bool highContrast = false}) =>
      _build(Brightness.dark, highContrast);

  static ThemeData _build(Brightness brightness, bool highContrast) {
    final scheme = highContrast
        ? AppColors.highContrast(brightness)
        : AppColors.scheme(brightness);
    final onSurface = scheme.onSurface;
    final onSurfaceVariant = scheme.onSurfaceVariant;
    final primary = scheme.primary;
    final onPrimary = scheme.onPrimary;

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      dividerColor: highContrast ? scheme.outline : scheme.outlineVariant,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
    );

    final textTheme = _textTheme(base.textTheme, onSurface, onSurfaceVariant);
    final outlineSide = BorderSide(
      color: highContrast ? scheme.outline : scheme.outlineVariant,
      width: highContrast ? 1.5 : 1,
    );

    return base.copyWith(
      textTheme: textTheme,
      // Keyboard focus gets a visible tonal state without introducing a new
      // ring language; high contrast makes it a solid, legible state layer.
      focusColor: highContrast ? primary : primary.withValues(alpha: 0.18),
      hoverColor: highContrast
          ? primary.withValues(alpha: 0.28)
          : onSurface.withValues(alpha: 0.06),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        centerTitle: false,
        titleSpacing: AppDimens.pageMargin,
        titleTextStyle: AppTextStyle.title3.copyWith(color: onSurface),
        toolbarHeight: AppDimens.toolbarHeight,
        actionsIconTheme: IconThemeData(color: onSurfaceVariant),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusCard),
          side: outlineSide,
        ),
      ),
      listTileTheme: ListTileThemeData(
        minLeadingWidth: 24,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppDimens.rowInset,
          vertical: AppDimens.space4,
        ),
        textColor: onSurface,
        subtitleTextStyle: AppTextStyle.bodyMedium.copyWith(
          color: onSurfaceVariant,
        ),
        iconColor: primary,
        minTileHeight: AppDimens.listHeight,
        selectedTileColor: scheme.primaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          disabledBackgroundColor: primary.withValues(alpha: 0.12),
          disabledForegroundColor: onSurface.withValues(alpha: 0.38),
          minimumSize: const Size(64, AppDimens.touchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppDimens.space20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
          ),
          textStyle: AppTextStyle.button,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(64, AppDimens.touchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppDimens.space20),
          side: BorderSide(color: scheme.outlineVariant, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
          ),
          textStyle: AppTextStyle.button,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(48, AppDimens.touchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppDimens.space12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusSmall),
          ),
          textStyle: AppTextStyle.button,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(AppDimens.touchTarget, AppDimens.touchTarget),
          foregroundColor: onSurfaceVariant,
          shape: const StadiumBorder(),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        selectedColor: scheme.primaryContainer,
        disabledColor: scheme.surfaceContainer.withValues(alpha: 0.5),
        labelStyle: AppTextStyle.labelLarge.copyWith(color: onSurface),
        secondaryLabelStyle: AppTextStyle.labelLarge.copyWith(
          color: scheme.onPrimaryContainer,
        ),
        side: BorderSide.none,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.space12,
          vertical: AppDimens.space6,
        ),
      ),
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerLow),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shadowColor: const WidgetStatePropertyAll(Colors.transparent),
        hintStyle: WidgetStatePropertyAll(
          AppTextStyle.bodyLarge.copyWith(color: onSurfaceVariant),
        ),
        textStyle: WidgetStatePropertyAll(
          AppTextStyle.bodyLarge.copyWith(color: onSurface),
        ),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(AppDimens.radiusStandard),
            ),
          ),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: AppDimens.space12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppDimens.space16,
          vertical: AppDimens.space16,
        ),
        hintStyle: AppTextStyle.bodyLarge.copyWith(color: onSurfaceVariant),
        labelStyle: AppTextStyle.bodyLarge.copyWith(color: onSurfaceVariant),
        floatingLabelStyle: AppTextStyle.bodySmall.copyWith(color: primary),
        border: _fieldBorder(scheme.outlineVariant),
        enabledBorder: _fieldBorder(scheme.outlineVariant),
        focusedBorder: _fieldBorder(primary, width: 1.5),
        errorBorder: _fieldBorder(scheme.error),
        focusedErrorBorder: _fieldBorder(scheme.error, width: 1.5),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: AppDimens.elevationLevel3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusDialog),
          side: outlineSide,
        ),
        titleTextStyle: AppTextStyle.title2.copyWith(color: onSurface),
        contentTextStyle: AppTextStyle.bodyMedium.copyWith(
          color: onSurfaceVariant,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        modalBackgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: AppDimens.elevationSheet,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppDimens.radiusSheet),
          ),
        ),
        showDragHandle: false,
        dragHandleColor: scheme.onSurfaceVariant.withValues(alpha: 0.4),
        dragHandleSize: const Size(32, 4),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: AppTextStyle.bodyMedium.copyWith(
          color: scheme.onInverseSurface,
        ),
        actionTextColor: scheme.inversePrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
        ),
        insetPadding: const EdgeInsets.symmetric(
          horizontal: AppDimens.space16,
          vertical: AppDimens.space16,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: AppDimens.navBarHeight,
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: const StadiumBorder(),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return AppTextStyle.labelMedium.copyWith(
            color: selected ? scheme.onPrimaryContainer : onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: AppDimens.iconMedium,
            color: selected ? scheme.onPrimaryContainer : onSurfaceVariant,
          );
        }),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return onSurface.withValues(alpha: 0.38);
          }
          if (states.contains(WidgetState.selected)) return scheme.onPrimary;
          return scheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return onSurface.withValues(alpha: 0.12);
          }
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return scheme.surfaceContainerHighest;
        }),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? scheme.primaryContainer
                : Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : onSurfaceVariant;
          }),
          side: WidgetStatePropertyAll(outlineSide),
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          textStyle: const WidgetStatePropertyAll(AppTextStyle.labelLarge),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: scheme.primaryContainer,
        circularTrackColor: scheme.primaryContainer,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(
          onSurfaceVariant.withValues(alpha: 0.5),
        ),
        radius: const Radius.circular(4),
        thickness: const WidgetStatePropertyAll(4),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: AppDimens.elevationLevel3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusPopup),
          side: outlineSide,
        ),
        textStyle: AppTextStyle.bodyLarge.copyWith(color: onSurface),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(AppDimens.radiusExtraSmall),
        ),
        textStyle: AppTextStyle.bodySmall.copyWith(
          color: scheme.onInverseSurface,
        ),
        waitDuration: const Duration(milliseconds: 400),
      ),
      pageTransitionsTheme: kNexaPageTransitions,
    );
  }

  static OutlineInputBorder _fieldBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
        borderSide: BorderSide(color: color, width: width),
      );

  static TextTheme _textTheme(
    TextTheme base,
    Color onSurface,
    Color onSurfaceVariant,
  ) {
    return base
        .copyWith(
          displayLarge: AppTextStyle.display,
          displayMedium: AppTextStyle.heroTitle,
          displaySmall: AppTextStyle.title1,
          headlineLarge: AppTextStyle.title1,
          headlineMedium: AppTextStyle.title2,
          headlineSmall: AppTextStyle.title3,
          titleLarge: AppTextStyle.title3,
          titleMedium: AppTextStyle.titleMedium,
          titleSmall: AppTextStyle.titleSmall,
          bodyLarge: AppTextStyle.bodyLarge,
          bodyMedium: AppTextStyle.bodyMedium,
          bodySmall: AppTextStyle.bodySmall,
          labelLarge: AppTextStyle.labelLarge,
          labelMedium: AppTextStyle.labelMedium,
          labelSmall: AppTextStyle.labelSmall,
        )
        .apply(
          bodyColor: onSurface,
          displayColor: onSurface,
          decorationColor: onSurfaceVariant,
        );
  }

  // Compatibility helpers used by legacy widget code.
  static Color surfaceElevatedFor(Brightness brightness) =>
      AppColors.surfaceElevatedFor(brightness);
}
