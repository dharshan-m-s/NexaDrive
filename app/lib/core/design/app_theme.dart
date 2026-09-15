import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_dimensions.dart';
import 'app_typography.dart';
import 'app_transitions.dart';

/// NexaDrive One UI theme builder.
///
/// Builds the application's ThemeData from the centralized design tokens.
/// The theme encodes One UI's feel:
/// - flat surfaces with subtle separation (no giant shadows)
/// - restrained single accent (One UI blue)
/// - controlled list rhythm (soft-rounded grouped rows)
/// - generous touch targets and natural dialogs/sheets
///
/// Visual rules:
/// - Light mode keeps surfaces white on a soft neutral page background.
/// - Dark mode uses One UI's deep neutral surfaces — never a simple inversion.
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final background = isDark ? AppColors.backgroundDark : AppColors.backgroundLight;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final surfaceAlt = isDark ? AppColors.surfaceAltDark : AppColors.surfaceAltLight;
    final onSurface = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final accent = AppColors.accentFor(brightness);
    final accentContainer = AppColors.accentContainerFor(brightness);
    final onAccentContainer = AppColors.onAccentContainerFor(brightness);
    final textSecondary = AppColors.textSecondaryFor(brightness);
    final textTertiary = AppColors.textTertiaryFor(brightness);
    final divider = AppColors.dividerFor(brightness);
    final error = isDark ? AppColors.errorDark : AppColors.errorLight;

    const ColorScheme scheme = ColorScheme.light();
    final colorScheme = scheme.copyWith(
      brightness: brightness,
      primary: accent,
      onPrimary: isDark ? AppColors.textOnPrimaryDark : AppColors.textOnPrimaryLight,
      primaryContainer: accentContainer,
      onPrimaryContainer: onAccentContainer,
      secondary: accent,
      onSecondary: isDark ? AppColors.textOnPrimaryDark : AppColors.textOnPrimaryLight,
      secondaryContainer: accentContainer,
      onSecondaryContainer: onAccentContainer,
      tertiary: accent,
      onTertiary: isDark ? AppColors.textOnPrimaryDark : AppColors.textOnPrimaryLight,
      // ------------------------------------------------- surface hierarchy
      // L0 page background -> L1 surface -> L2 grouped alt -> L3 bars.
      surface: surface,
      onSurface: onSurface,
      surfaceContainerLowest: background,
      surfaceContainerLow: surface,
      surfaceContainer: surfaceAlt,
      surfaceContainerHigh: isDark
          ? AppColors.surfacePressedDark
          : AppColors.surfacePressedLight,
      surfaceContainerHighest: surfaceAlt,
      onSurfaceVariant: textSecondary,
      outline: textTertiary,
      outlineVariant: divider,
      // status containers give Material chips/alerts One UI tonal status
      error: error,
      onError: Colors.white,
      errorContainer: AppColors.errorContainerFor(brightness),
      onErrorContainer: AppColors.onErrorContainerFor(brightness),
      inversePrimary: AppColors.accentTextFor(brightness),
      shadow: AppColors.shadowColorSoft,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      shadowColor: AppColors.shadowColorSoft,
      dividerColor: divider,
    );

    return base.copyWith(
      textTheme: _textTheme(base.textTheme, onSurface, textSecondary, textTertiary),
      // -------------------------------------------------- component themes
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: onSurface,
        elevation: AppDimens.elevationNone,
        scrolledUnderElevation: AppDimens.elevationSubtle,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimaryLight,
        ).copyWith(color: onSurface),
        toolbarHeight: 56,
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: AppDimens.elevationNone,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusTile),
        ),
      ),
      listTileTheme: ListTileThemeData(
        minLeadingWidth: AppDimens.iconTileLarge,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppDimens.space16,
          vertical: AppDimens.space4,
        ),
        textColor: onSurface,
        subtitleTextStyle: TextStyle(height: 1.2, color: textSecondary),
        iconColor: onSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusTile),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: isDark ? AppColors.textOnPrimaryDark : Colors.white,
          disabledBackgroundColor: accent.withValues(alpha: 0.4),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.8),
          minimumSize: const Size(64, AppDimens.touchTarget),
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.space24,
            vertical: AppDimens.space12,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusPill),
          ),
          textStyle: AppTextStyle.button,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          minimumSize: const Size(64, AppDimens.touchTarget),
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.space24,
            vertical: AppDimens.space12,
          ),
          side: BorderSide(color: accent, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusPill),
          ),
          textStyle: AppTextStyle.button,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accentTextFor(brightness),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusPill),
          ),
          textStyle: AppTextStyle.buttonSmall,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(AppDimens.touchTarget, AppDimens.touchTarget),
          foregroundColor: onSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusInner),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceAlt,
        selectedColor: accentContainer,
        disabledColor: surfaceAlt,
        labelStyle: AppTextStyle.chipLabel.copyWith(color: textSecondary),
        secondaryLabelStyle: AppTextStyle.chipLabel.copyWith(color: onAccentContainer),
        side: const BorderSide(color: Colors.transparent),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.space12,
          vertical: AppDimens.space8,
        ),
      ),
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(surfaceAlt),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        hintStyle: WidgetStatePropertyAll(TextStyle(color: textTertiary)),
        textStyle: WidgetStatePropertyAll(TextStyle(color: onSurface)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusInner),
          ),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: AppDimens.space12),
        ),
      ),
      bottomAppBarTheme: BottomAppBarThemeData(
        color: isDark ? AppColors.surfaceElevatedDark : AppColors.surfaceElevatedLight,
        elevation: AppDimens.elevationNone,
        surfaceTintColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: AppDimens.space16),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppDimens.space16,
          vertical: AppDimens.space16,
        ),
        hintStyle: TextStyle(color: textTertiary, fontWeight: FontWeight.w400),
        labelStyle: TextStyle(color: textSecondary, fontWeight: FontWeight.w400),
        floatingLabelStyle: TextStyle(color: accent, fontWeight: FontWeight.w600),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusInner),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusInner),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusInner),
          borderSide: BorderSide(color: accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusInner),
          borderSide: BorderSide(color: error, width: 1.5),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: AppDimens.elevationSheet,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusDialog),
        ),
        titleTextStyle: AppTextStyle.dialogTitle.copyWith(color: onSurface),
        contentTextStyle: AppTextStyle.rowSubtitle.copyWith(color: textSecondary),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: AppDimens.elevationSheet,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppDimens.radiusSheet)),
        ),
        showDragHandle: true,
        dragHandleColor: divider,
        dragHandleSize: const Size(36, 4),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFF2D2E30) : const Color(0xFF1A1C1E),
        contentTextStyle: const TextStyle(fontSize: 14, color: Colors.white),
        actionTextColor: AppColors.accentDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusInner),
        ),
        insetPadding: const EdgeInsets.symmetric(
          horizontal: AppDimens.space16,
          vertical: AppDimens.space12,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: divider,
        thickness: 1,
        space: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: AppDimens.bottomNavHeight,
        backgroundColor: surfaceElevatedFor(brightness),
        surfaceTintColor: Colors.transparent,
        indicatorColor: accentContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            // selected label uses onAccentContainer (passes AA on container)
            color: selected ? onAccentContainer : textSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: AppDimens.iconMedium,
            color: selected ? accent : textSecondary,
          );
        }),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return selected ? accent : divider.withValues(alpha: 0.6);
        }),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        thumbColor: const WidgetStatePropertyAll(Colors.white),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? accentContainer
                : Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? onAccentContainer
                : textSecondary;
          }),
          side: WidgetStatePropertyAll(BorderSide(color: divider)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDimens.radiusPill),
            ),
          ),
          textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 13)),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: surfaceAlt,
        circularTrackColor: surfaceAlt,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(
          textTertiary.withValues(alpha: 0.5),
        ),
        radius: const Radius.circular(4),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusInner),
        ),
        textStyle: AppTextStyle.rowTitle.copyWith(
          color: onSurface,
          fontSize: 14,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2D2E30) : const Color(0xFF1A1C1E),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(fontSize: 13, color: Colors.white),
        waitDuration: const Duration(milliseconds: 400),
      ),
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: kOneUiPageTransitions,
    );
  }

  static Color surfaceElevatedFor(Brightness brightness) =>
      brightness == Brightness.dark
          ? AppColors.surfaceElevatedDark
          : AppColors.surfaceElevatedLight;

  static TextTheme _textTheme(
    TextTheme base,
    Color onSurface,
    Color textSecondary,
    Color textTertiary,
  ) {
    return base
        .copyWith(
          displayLarge: const TextStyle(
              fontSize: 32, fontWeight: FontWeight.w700, height: 1.2),
          displayMedium: const TextStyle(
              fontSize: 26, fontWeight: FontWeight.w600, height: 1.2),
          displaySmall: AppTextStyle.display,
          headlineLarge: AppTextStyle.pageTitle,
          headlineMedium: AppTextStyle.sectionHeader,
          titleLarge: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.w600, height: 1.3),
          titleMedium: AppTextStyle.rowTitle,
          bodyLarge: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w400, height: 1.4),
          bodyMedium: AppTextStyle.rowSubtitle,
          bodySmall: AppTextStyle.caption,
          labelLarge: AppTextStyle.button,
          labelMedium: AppTextStyle.buttonSmall,
          labelSmall: AppTextStyle.micro,
        )
        .apply(
          bodyColor: onSurface,
          displayColor: onSurface,
          // Keep secondary/tertiary readable at their own contrast level.
        );
  }
}