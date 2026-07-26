import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Material 3 theme with Charis branding
class AppTheme {
  AppTheme._();

  static const String _fontFamily = 'Questrial';

  /// Light theme ColorScheme: Charis reds + neutrals only (no seed-derived pink).
  static const ColorScheme _lightColorScheme = ColorScheme.light(
    primary: AppColors.charisRedPrimary,
    onPrimary: AppColors.charisWhite,
    primaryContainer: AppColors.charisLightGray,
    onPrimaryContainer: AppColors.charisBlack,
    secondary: AppColors.charisRedLight,
    onSecondary: AppColors.charisWhite,
    secondaryContainer: AppColors.charisLightGray,
    onSecondaryContainer: AppColors.charisDarkGray,
    tertiary: AppColors.charisMidGray,
    onTertiary: AppColors.charisWhite,
    tertiaryContainer: AppColors.charisLightGray,
    onTertiaryContainer: AppColors.charisDarkGray,
    error: AppColors.charisRedDark,
    onError: AppColors.charisWhite,
    errorContainer: Color(0x1A58001d), // light tint of charisRedDark
    onErrorContainer: AppColors.charisRedDark,
    surface: AppColors.charisWhite,
    onSurface: AppColors.charisBlack,
    surfaceContainerHighest: AppColors.charisLightGray,
    surfaceContainer: AppColors.charisWhite,
    onSurfaceVariant: AppColors.charisDarkGray,
    outline: AppColors.borderLight,
    outlineVariant: AppColors.borderLight,
    inverseSurface: AppColors.charisBlack,
    onInverseSurface: AppColors.charisWhite,
    shadow: AppColors.charisBlack,
    scrim: AppColors.charisBlack,
    inversePrimary: AppColors.charisRedLight,
  );

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: _fontFamily,
      colorScheme: _lightColorScheme,
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontFamily: _fontFamily,
          fontWeight: FontWeight.w700,
          fontSize: 32,
          color: AppColors.charisBlack,
        ),
        displayMedium: TextStyle(
          fontFamily: _fontFamily,
          fontWeight: FontWeight.w700,
          fontSize: 28,
          color: AppColors.charisBlack,
        ),
        displaySmall: TextStyle(
          fontFamily: _fontFamily,
          fontWeight: FontWeight.w700,
          fontSize: 24,
          color: AppColors.charisBlack,
        ),
        headlineMedium: TextStyle(
          fontFamily: _fontFamily,
          fontWeight: FontWeight.w700,
          fontSize: 20,
          color: AppColors.charisBlack,
        ),
        titleLarge: TextStyle(
          fontFamily: _fontFamily,
          fontWeight: FontWeight.w600,
          fontSize: 18,
          color: AppColors.charisBlack,
        ),
        bodyLarge: TextStyle(
          fontFamily: _fontFamily,
          fontWeight: FontWeight.normal,
          fontSize: 16,
          color: AppColors.charisBlack,
        ),
        bodyMedium: TextStyle(
          fontFamily: _fontFamily,
          fontWeight: FontWeight.normal,
          fontSize: 14,
          color: AppColors.charisDarkGray,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.charisWhite,
        foregroundColor: AppColors.charisBlack,
        elevation: 1,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: _fontFamily,
          fontWeight: FontWeight.w700,
          fontSize: 20,
          color: AppColors.charisBlack,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.charisRedPrimary,
          foregroundColor: AppColors.charisWhite,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(
            fontFamily: _fontFamily,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.charisRedPrimary;
            }
            return AppColors.charisWhite;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.charisWhite;
            }
            return AppColors.charisDarkGray;
          }),
          side: WidgetStateProperty.all(
            const BorderSide(color: AppColors.borderLight),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.charisWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        titleTextStyle: const TextStyle(
          fontFamily: _fontFamily,
          fontWeight: FontWeight.w600,
          fontSize: 20,
          color: AppColors.charisBlack,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: _fontFamily,
          fontSize: 14,
          color: AppColors.charisDarkGray,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: AppColors.charisWhite,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(
            color: AppColors.primaryActionRed,
            width: 2,
          ),
        ),
        filled: true,
        fillColor: AppColors.charisWhite,
      ),
    );
  }

  /// Dark theme ColorScheme: Charis reds + neutrals only.
  static const ColorScheme _darkColorScheme = ColorScheme.dark(
    primary: AppColors.primaryActionRed,
    onPrimary: AppColors.charisWhite,
    primaryContainer: AppColors.surfaceDarkElevated,
    onPrimaryContainer: AppColors.textOnDark,
    secondary: AppColors.textSecondaryOnDark,
    onSecondary: AppColors.surfaceDark,
    secondaryContainer: AppColors.surfaceDarkElevated,
    onSecondaryContainer: AppColors.textSecondaryOnDark,
    tertiary: AppColors.charisMidGray,
    onTertiary: AppColors.textOnDark,
    tertiaryContainer: AppColors.surfaceDarkElevated,
    onTertiaryContainer: AppColors.textSecondaryOnDark,
    error: AppColors.charisRedDark,
    onError: AppColors.charisWhite,
    errorContainer: Color(0x33CC3B3B), // dark red tint
    onErrorContainer: AppColors.charisWhite,
    surface: AppColors.surfaceDark,
    onSurface: AppColors.textOnDark,
    surfaceContainerHighest: AppColors.surfaceDarkElevated,
    surfaceContainer: AppColors.surfaceDarkElevated,
    onSurfaceVariant: AppColors.textSecondaryOnDark,
    outline: AppColors.borderDark,
    outlineVariant: AppColors.borderDark,
    inverseSurface: AppColors.textOnDark,
    onInverseSurface: AppColors.surfaceDark,
    shadow: AppColors.charisBlack,
    scrim: AppColors.charisBlack,
    inversePrimary: AppColors.charisRedDark,
  );

  /// Dark theme for app shell, list, sidebar; modals use surfaceDarkElevated.
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: _fontFamily,
      brightness: Brightness.dark,
      colorScheme: _darkColorScheme,
      scaffoldBackgroundColor: AppColors.surfaceDark,
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontFamily: _fontFamily,
          fontWeight: FontWeight.w700,
          fontSize: 32,
          color: AppColors.textOnDark,
        ),
        displayMedium: TextStyle(
          fontFamily: _fontFamily,
          fontWeight: FontWeight.w700,
          fontSize: 28,
          color: AppColors.textOnDark,
        ),
        displaySmall: TextStyle(
          fontFamily: _fontFamily,
          fontWeight: FontWeight.w700,
          fontSize: 24,
          color: AppColors.textOnDark,
        ),
        headlineMedium: TextStyle(
          fontFamily: _fontFamily,
          fontWeight: FontWeight.w700,
          fontSize: 20,
          color: AppColors.textOnDark,
        ),
        titleLarge: TextStyle(
          fontFamily: _fontFamily,
          fontWeight: FontWeight.w600,
          fontSize: 18,
          color: AppColors.textOnDark,
        ),
        bodyLarge: TextStyle(
          fontFamily: _fontFamily,
          fontWeight: FontWeight.normal,
          fontSize: 16,
          color: AppColors.textOnDark,
        ),
        bodyMedium: TextStyle(
          fontFamily: _fontFamily,
          fontWeight: FontWeight.normal,
          fontSize: 14,
          color: AppColors.textSecondaryOnDark,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryActionRed,
          foregroundColor: AppColors.charisWhite,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(
            fontFamily: _fontFamily,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textSecondaryOnDark,
          side: const BorderSide(color: AppColors.borderDark),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primaryActionRed;
            }
            return AppColors.surfaceDark;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.charisWhite;
            }
            return AppColors.textSecondaryOnDark;
          }),
          side: WidgetStateProperty.all(
            const BorderSide(color: AppColors.borderDark),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceDarkElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        titleTextStyle: const TextStyle(
          fontFamily: _fontFamily,
          fontWeight: FontWeight.w600,
          fontSize: 20,
          color: AppColors.textOnDark,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: _fontFamily,
          fontSize: 14,
          color: AppColors.textSecondaryOnDark,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: AppColors.surfaceDarkElevated,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.borderDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.borderDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(
            color: AppColors.primaryActionRed,
            width: 2,
          ),
        ),
        filled: true,
        fillColor: AppColors.surfaceDark,
      ),
    );
  }
}
