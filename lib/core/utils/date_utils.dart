import 'package:intl/intl.dart';

/// Date formatting and parsing utilities
class DateUtils {
  DateUtils._();

  static final DateFormat _displayFormat = DateFormat('dd MMM yyyy');
  static final DateFormat _isoFormat = DateFormat('yyyy-MM-dd');

  /// Format date for display (e.g., "28 Jan 2026")
  static String formatDisplayDate(DateTime date) {
    return _displayFormat.format(date);
  }

  /// Ordinal suffix for day (e.g. 1 -> "st", 2 -> "nd", 28 -> "th")
  static String _ordinal(int day) {
    if (day >= 11 && day <= 13) return 'th';
    switch (day % 10) {
      case 1:
        return 'st';
      case 2:
        return 'nd';
      case 3:
        return 'rd';
      default:
        return 'th';
    }
  }

  /// Format date for attendance screen (e.g., "January 28th, 2026")
  static String formatAttendanceDate(DateTime date) {
    final month = DateFormat('MMMM').format(date);
    final day = date.day;
    return '$month ${day}${_ordinal(day)}, ${date.year}';
  }

  /// Format date as ISO string (e.g., "2026-01-28")
  static String formatIsoDate(DateTime date) {
    return _isoFormat.format(date);
  }

  /// Parse ISO date string to DateTime
  static DateTime? parseIsoDate(String dateString) {
    try {
      return _isoFormat.parse(dateString);
    } catch (e) {
      return null;
    }
  }

  /// Get today's date (without time)
  static DateTime today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }
}
