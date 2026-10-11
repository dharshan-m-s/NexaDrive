import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_dimensions.dart';
import 'app_typography.dart';
import 'app_transitions.dart';

/// NexaDrive theme builder.
///
/// THE REFERENCE: Apple's platform UI. The theme encodes iOS's feel:
///  * layered surfaces — a grouped page background behind white content planes;
///  * no ripple — press feedback is a quiet tonal highlight, as on iOS;
///  * restrained single accent (system blue) and no tinted surface overlays;
///  * grouped inset lists, generous rounded panels and natural sheets/alerts.
///
/// Visual rules:
///  * Light mode: grouped neutral page background, white content surfaces.
///  * Dark mode: true-black grouped canvas, `#1C1C1E`/`#2C2C2E` content planes.
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final background =
        isDark ? AppColors.backgroundDark : AppColors.backgroundLight;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final surfaceAlt =
        isDark ? AppColors.surfaceAltDark : AppColors.surfaceAltLight;
    final onSurface =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final accent = AppColors.accentFor(brightness);
    final accentContainer = AppColors.accentContainerFor(brightness);
    final onAccentContainer = AppColors.onAccentContainerFor(brightness);
    final textSecondary = AppColors.textSecondaryFor(brightness);
    final textTertiary = AppColors.textTertiaryFor(brightness);
    final divider = AppColors.dividerFor(brightness);
    final error = isDark ? AppColors.errorDark : AppColors.errorLight;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: Colors.white,
      primaryContainer: accentContainer,
      onPrimaryContainer: onAccentContainer,
      secondary: accent,
      onSecondary: Colors.white,
      secondaryContainer: accentContainer,
      onSecondaryContainer: onAccentContainer,
      tertiary: accent,
      onTertiary: Colors.white,
      error: error,
      onError: Colors.white,
      errorContainer: AppColors.errorContainerFor(brightness),
      onErrorContainer: AppColors.onErrorContainerFor(brightness),
      surface: surface,
      onSurface: onSurface,
      surfaceContainerLowest: background,
      surfaceContainerLow: surface,
      surfaceContainer: surfaceAlt,
      surfaceContainerHigh: AppColors.surfacePressedFor(brightness),
      surfaceContainerHighest: surfaceAlt,
      onSurfaceVariant: textSecondary,
      outline: AppColors.separatorOpaqueFor(brightness),
      outlineVariant: divider,
      inversePrimary: accent,
      shadow: isDark ? AppColors.shadowColorStrong : AppColors.shadowColorSoft,
      scrim: AppColors.scrim,
      inverseSurface: isDark ? AppColors.surfaceLight : AppColors.surfaceDark,
      onInverseSurface:
          isDark ? AppColors.textPrimaryLight : AppColors.textPrimaryDark,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      shadowColor:
          isDark ? AppColors.shadowColorStrong : AppColors.shadowColorSoft,
      dividerColor: divider,
      // iOS has no ripple: press feedback is a faint tonal highlight instead.
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
    );

    final textTheme =
        _textTheme(base.textTheme, onSurface, textSecondary, textTertiary);

    return base.copyWith(
      textTheme: textTheme,
      // -------------------------------------------------- component themes
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: AppTextStyle.sectionHeader.copyWith(color: onSurface),
        toolbarHeight: AppDimens.toolbarHeight,
        systemOverlayStyle: null,
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        ),
      ),
      listTileTheme: ListTileThemeData(
        minLeadingWidth: 24,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppDimens.rowInset,
          vertical: AppDimens.space2,
        ),
        textColor: onSurface,
        subtitleTextStyle: AppTextStyle.rowSubtitle.copyWith(
          color: textSecondary,
        ),
        iconColor: accent,
        minTileHeight: AppDimens.listHeight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusTile),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: accent.withValues(alpha: 0.35),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.7),
          minimumSize: const Size(64, AppDimens.touchTarget),
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.space20,
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
            horizontal: AppDimens.space20,
            vertical: AppDimens.space12,
          ),
          side: BorderSide(color: accent.withValues(alpha: 0.5), width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusPill),
          ),
          textStyle: AppTextStyle.button,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          minimumSize: const Size(44, AppDimens.touchTarget),
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
            borderRadius: BorderRadius.circular(AppDimens.radiusSmall),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceAlt,
        selectedColor: accentContainer,
        disabledColor: surfaceAlt,
        labelStyle: AppTextStyle.chipLabel.copyWith(color: onSurface),
        secondaryLabelStyle:
            AppTextStyle.chipLabel.copyWith(color: onAccentContainer),
        side: BorderSide.none,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.space12,
          vertical: AppDimens.space6,
        ),
      ),
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(
          brightness == Brightness.dark
              ? AppColors.surfaceAltDark
              : AppColors.fillFor(brightness),
        ),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shadowColor: const WidgetStatePropertyAll(Colors.transparent),
        hintStyle: WidgetStatePropertyAll(
          AppTextStyle.body.copyWith(color: textTertiary),
        ),
        textStyle: WidgetStatePropertyAll(
          AppTextStyle.body.copyWith(color: onSurface),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
          ),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: AppDimens.space12),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brightness == Brightness.dark
            ? AppColors.surfaceAltDark
            : AppColors.fillFor(brightness),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppDimens.space16,
          vertical: AppDimens.space16,
        ),
        hintStyle: AppTextStyle.body.copyWith(color: textTertiary),
        labelStyle: AppTextStyle.body.copyWith(color: textSecondary),
        floatingLabelStyle: AppTextStyle.caption.copyWith(color: accent),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
          borderSide: BorderSide(color: accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
          borderSide: BorderSide(color: error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
          borderSide: BorderSide(color: error, width: 2),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor:
            isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusDialog),
        ),
        titleTextStyle: AppTextStyle.dialogTitle.copyWith(color: onSurface),
        contentTextStyle:
            AppTextStyle.rowSubtitle.copyWith(color: textSecondary),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor:
            isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        modalBackgroundColor:
            isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppDimens.radiusSheet),
          ),
        ),
        showDragHandle: false,
        dragHandleColor: textTertiary,
        dragHandleSize: const Size(36, 5),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            isDark ? const Color(0xFF2C2C2E) : const Color(0xFF1C1C1E),
        contentTextStyle: const TextStyle(fontSize: 15, color: Colors.white),
        actionTextColor: AppColors.accentDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
        ),
        insetPadding: const EdgeInsets.symmetric(
          horizontal: AppDimens.space16,
          vertical: AppDimens.space12,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: divider,
        thickness: 0.5,
        space: 0.5,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: AppDimens.bottomNavHeight,
        backgroundColor: surfaceElevatedFor(brightness),
        surfaceTintColor: Colors.transparent,
        indicatorColor: accentContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        ),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return AppTextStyle.navLabel.copyWith(
            color: selected ? accent : textSecondary,
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
          return selected
              ? AppColors.successFor(brightness)
              : divider.withValues(alpha: 0.8);
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
                : onSurface;
          }),
          side: WidgetStatePropertyAll(BorderSide(color: divider)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDimens.radiusSmall),
            ),
          ),
          textStyle: const WidgetStatePropertyAll(AppTextStyle.caption),
          visualDensity: VisualDensity.compact,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: surfaceAlt,
        circularTrackColor: surfaceAlt,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(
          textTertiary.withValues(alpha: 0.6),
        ),
        radius: const Radius.circular(3),
        thickness: const WidgetStatePropertyAll(3),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: isDark ? AppColors.surfaceAltDark : AppColors.surfaceLight,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusPopup),
        ),
        textStyle: AppTextStyle.rowTitle.copyWith(color: onSurface),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(AppDimens.radiusSmall),
        ),
        textStyle: const TextStyle(fontSize: 13, color: Colors.white),
        waitDuration: const Duration(milliseconds: 400),
      ),
      pageTransitionsTheme: kNexaPageTransitions,
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
          displayLarge: AppTextStyle.display,
          displayMedium: AppTextStyle.largeTitle,
          displaySmall: AppTextStyle.pageTitle,
          headlineLarge: AppTextStyle.title1,
          headlineMedium: AppTextStyle.title2,
          headlineSmall: AppTextStyle.title3,
          titleLarge: AppTextStyle.title2,
          titleMedium: AppTextStyle.rowTitle,
          titleSmall: AppTextStyle.callout,
          bodyLarge: AppTextStyle.body,
          bodyMedium: AppTextStyle.subheadline,
          bodySmall: AppTextStyle.footnote,
          labelLarge: AppTextStyle.button,
          labelMedium: AppTextStyle.buttonSmall,
          labelSmall: AppTextStyle.caption,
        )
        .apply(
          bodyColor: onSurface,
          displayColor: onSurface,
        );
  }
}
