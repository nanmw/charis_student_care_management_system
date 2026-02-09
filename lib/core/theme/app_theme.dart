import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Material 3 theme with Charis branding
class AppTheme {
  AppTheme._();

  static const String _fontFamily = 'Questrial';

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: _fontFamily,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.charisRedPrimary,
        primary: AppColors.charisRedPrimary,
        secondary: AppColors.charisRedLight,
        surface: AppColors.charisWhite,
        error: AppColors.charisRedDark,
      ),
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
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: AppColors.charisWhite,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.charisMidGray),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.charisMidGray),
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

  /// Dark theme for app shell, list, sidebar; modals use light card.
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: _fontFamily,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primaryActionRed,
        surface: AppColors.surfaceDark,
        onSurface: AppColors.textOnDark,
        onPrimary: AppColors.charisWhite,
        secondary: AppColors.textSecondaryOnDark,
      ),
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
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textSecondaryOnDark,
          side: const BorderSide(color: AppColors.charisMidGray),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: AppColors.charisWhite,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceDarkElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.charisMidGray),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.charisMidGray),
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
}
