import 'package:intl/intl.dart';

/// Currency formatting utilities for Rand (ZAR)
class CurrencyUtils {
  CurrencyUtils._();

  static final NumberFormat _currencyFormat = NumberFormat.currency(
    symbol: 'R ',
    decimalDigits: 2,
    locale: 'en_ZA',
  );

  /// Format amount as Rand currency (e.g., "R 19,800.00")
  static String formatRand(double amount) {
    return _currencyFormat.format(amount);
  }

  /// Parse currency string to double
  static double? parseRand(String currencyString) {
    try {
      // Remove "R " prefix and commas, then parse
      final cleaned = currencyString
          .replaceAll('R', '')
          .replaceAll(' ', '')
          .replaceAll(',', '');
      return double.parse(cleaned);
    } catch (e) {
      return null;
    }
  }
}
