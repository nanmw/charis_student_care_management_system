import 'package:flutter/material.dart';

/// Charis branding color palette
class AppColors {
  AppColors._();

  // Charis Reds (Primary)
  static const Color charisRedDark = Color(0xFF58001d); // #58001d
  static const Color charisRedPrimary = Color(
    0xFF7d0023,
  ); // #7d0023 (primary buttons/accent)
  static const Color charisRedLight = Color(
    0xFF8b0029,
  ); // #8b0029 (lighter highlights)

  // Neutrals
  static const Color charisBlack = Color(0xFF151515); // #151515
  static const Color charisDarkGray = Color(0xFF2c2c2c); // #2c2c2c
  static const Color charisMidGray = Color(0xFF696969); // #696969
  static const Color charisLightGray = Color(0xFFe6e6e6); // #e6e6e6
  static const Color charisWhite = Color(0xFFffffff); // #ffffff

  // Dark UI (design: #1E1E1E background, red accents #CC3B3B)
  static const Color surfaceDark = Color(0xFF1E1E1E);
  static const Color surfaceDarkElevated = Color(0xFF2A2A2A);
  static const Color textOnDark = Color(0xFFffffff);
  static const Color textSecondaryOnDark = Color(0xFFb0b0b0);
  static const Color primaryActionRed = Color(0xFFCC3B3B);
  static const Color syncedGreen = Color(0xFF2E7D32);

  /// Light red background for Withdrawn status (e.g. in students list).
  static const Color withdrawnStatusBackground = Color(0x1ACC3B3B);

  /// Green color for Correspondence status border and text.
  static const Color correspondenceStatusGreen = Color(0xFF2E7D32);

  /// Light green background for Correspondence status (e.g. in students list).
  static const Color correspondenceStatusBackground = Color(0x1A2E7D32);
}
