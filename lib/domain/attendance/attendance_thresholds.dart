import 'package:charis_student_care/core/constants/app_constants.dart';
import 'package:charis_student_care/data/database/app_database.dart';

/// Period used for attendance threshold evaluation.
enum AttendanceThresholdPeriod { month, term, year }

/// Result of comparing present days to an expected-day threshold.
class AttendanceThresholdResult {
  const AttendanceThresholdResult({
    required this.period,
    required this.presentDays,
    required this.expectedDays,
  });

  final AttendanceThresholdPeriod period;
  final int presentDays;
  final int expectedDays;

  int get shortfall =>
      presentDays >= expectedDays ? 0 : expectedDays - presentDays;

  bool get met => presentDays >= expectedDays;

  double get percentOfExpected =>
      expectedDays > 0 ? (presentDays / expectedDays) * 100.0 : 0.0;
}

/// Resolved expected-day thresholds (from settings or AppConstants defaults).
class AttendanceThresholdConfig {
  const AttendanceThresholdConfig({
    required this.month,
    required this.term,
    required this.year,
  });

  final int month;
  final int term;
  final int year;

  static const AttendanceThresholdConfig defaults = AttendanceThresholdConfig(
    month: AppConstants.attendanceExpectedDaysPerMonth,
    term: AppConstants.attendanceExpectedDaysPerTerm,
    year: AppConstants.attendanceExpectedDaysPerYear,
  );

  static const AttendanceThresholdConfig hybridDefaults =
      AttendanceThresholdConfig(
    month: AppConstants.attendanceExpectedDaysHybridPerMonth,
    term: AppConstants.attendanceExpectedDaysHybridPerTerm,
    year: AppConstants.attendanceExpectedDaysHybridPerYear,
  );

  int forPeriod(AttendanceThresholdPeriod period) {
    switch (period) {
      case AttendanceThresholdPeriod.month:
        return month;
      case AttendanceThresholdPeriod.term:
        return term;
      case AttendanceThresholdPeriod.year:
        return year;
    }
  }
}

int expectedDaysForPeriod(
  AttendanceThresholdPeriod period, {
  int? expectedDays,
  AttendanceThresholdConfig? config,
}) {
  if (expectedDays != null) return expectedDays;
  if (config != null) return config.forPeriod(period);
  return AttendanceThresholdConfig.defaults.forPeriod(period);
}

/// Full-time and Hybrid expected-day triples.
class AttendanceThresholdsByMode {
  const AttendanceThresholdsByMode({
    required this.fullTime,
    required this.hybrid,
  });

  final AttendanceThresholdConfig fullTime;
  final AttendanceThresholdConfig hybrid;

  static const AttendanceThresholdsByMode defaults = AttendanceThresholdsByMode(
    fullTime: AttendanceThresholdConfig.defaults,
    hybrid: AttendanceThresholdConfig.hybridDefaults,
  );

  /// Hybrid students use [hybrid]; any other / null mode uses [fullTime].
  AttendanceThresholdConfig forMode(String? mode) {
    if (mode != null && mode.trim().toLowerCase() == 'hybrid') {
      return hybrid;
    }
    return fullTime;
  }
}

/// Counts present days among [records] whose date falls in [[start], [end]] (inclusive).
int presentDaysInRange(
  Iterable<AttendanceData> records,
  DateTime start,
  DateTime end,
) {
  final startDay = DateTime(start.year, start.month, start.day);
  final endDay = DateTime(end.year, end.month, end.day);
  var count = 0;
  for (final r in records) {
    if (r.present != 1) continue;
    final d = DateTime(r.date.year, r.date.month, r.date.day);
    if (!d.isBefore(startDay) && !d.isAfter(endDay)) {
      count++;
    }
  }
  return count;
}

AttendanceThresholdResult evaluateAttendanceThreshold({
  required AttendanceThresholdPeriod period,
  required int presentDays,
  int? expectedDays,
  AttendanceThresholdConfig? config,
}) {
  return AttendanceThresholdResult(
    period: period,
    presentDays: presentDays,
    expectedDays: expectedDaysForPeriod(
      period,
      expectedDays: expectedDays,
      config: config,
    ),
  );
}

/// Term bounds within a session year (Feb–Oct): T1 Feb–Apr, T2 May–Jul, T3 Aug–Oct.
(DateTime start, DateTime end) termDateRange(int sessionYear, int term) {
  switch (term) {
    case 1:
      return (DateTime(sessionYear, 2, 1), DateTime(sessionYear, 4, 30));
    case 2:
      return (DateTime(sessionYear, 5, 1), DateTime(sessionYear, 7, 31));
    case 3:
      return (DateTime(sessionYear, 8, 1), DateTime(sessionYear, 10, 31));
    default:
      return (DateTime(sessionYear, 2, 1), DateTime(sessionYear, 10, 31));
  }
}

/// Term number for a calendar month (Jan–Apr → 1, May–Jul → 2, Aug–Dec → 3).
int termNumberForMonth(int month) {
  if (month <= 4) return 1;
  if (month <= 7) return 2;
  return 3;
}

/// Inclusive calendar days from [start] through [end] (date-only, local).
/// Returns an empty list when [end] is before [start].
List<DateTime> calendarDaysInRange(DateTime start, DateTime end) {
  var day = DateTime(start.year, start.month, start.day);
  final last = DateTime(end.year, end.month, end.day);
  if (day.isAfter(last)) return const [];
  final days = <DateTime>[];
  while (!day.isAfter(last)) {
    days.add(day);
    day = DateTime(day.year, day.month, day.day + 1);
  }
  return days;
}

/// Calendar month bounds for [year]/[month].
(DateTime start, DateTime end) monthDateRange(int year, int month) {
  final start = DateTime(year, month, 1);
  final end = DateTime(year, month + 1, 0);
  return (start, end);
}

/// Full session year window Feb 1 – Oct 31.
(DateTime start, DateTime end) sessionYearDateRange(int sessionYear) {
  return (DateTime(sessionYear, 2, 1), DateTime(sessionYear, 10, 31));
}
