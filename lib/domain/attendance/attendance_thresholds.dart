import 'dart:convert';

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

/// YYYY-MM-DD from [date]'s year/month/day fields (no timezone conversion).
String attendanceDateStamp(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// Calendar-day stamps that may represent the same school day.
///
/// Rows are stored as UTC midnight, local midnight, or local midnight encoded
/// as the previous UTC evening. Matching any of these stamps to a column date
/// keeps ticks visible.
Set<String> attendanceDateStamps(DateTime date) {
  final local = date.toLocal();
  final utc = date.toUtc();
  final stamps = <String>{
    attendanceDateStamp(date),
    attendanceDateStamp(local),
    attendanceDateStamp(utc),
  };
  if (utc.hour >= 12) {
    final next = DateTime.utc(utc.year, utc.month, utc.day)
        .add(const Duration(days: 1));
    stamps.add(attendanceDateStamp(next));
  }
  return stamps;
}

bool attendanceDayInRange(DateTime date, DateTime start, DateTime end) {
  final startS = attendanceDateStamp(DateTime(start.year, start.month, start.day));
  final endS = attendanceDateStamp(DateTime(end.year, end.month, end.day));
  return attendanceDateStamps(date).any(
    (s) => s.compareTo(startS) >= 0 && s.compareTo(endS) <= 0,
  );
}

/// Counts present days among [records] whose date falls in [[start], [end]] (inclusive).
int presentDaysInRange(
  Iterable<AttendanceData> records,
  DateTime start,
  DateTime end,
) {
  var count = 0;
  for (final r in records) {
    if (r.present != 1) continue;
    if (attendanceDayInRange(r.date, start, end)) count++;
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

/// Calendar year for Feb–Oct term columns (not payment legacy year).
///
/// Prefers [startDate]'s year. For codes like `2025-2026`, uses the year whose
/// Feb–Oct window contains [now] (August 2026 → 2026). Single-year `2026` stays 2026.
int sessionCalendarYear({
  String? sessionCode,
  DateTime? startDate,
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  if (startDate != null) {
    return startDate.year;
  }
  final code = sessionCode?.trim();
  if (code == null || code.isEmpty) return today.year;
  final parts = code.split('-').where((p) => p.trim().isNotEmpty).toList();
  if (parts.length >= 2) {
    final years = <int>[];
    for (final p in parts) {
      final y = int.tryParse(p.trim());
      if (y != null) years.add(y);
    }
    if (years.length >= 2) {
      final day = DateTime(today.year, today.month, today.day);
      for (final y in years.reversed) {
        final start = DateTime(y, 2, 1);
        final end = DateTime(y, 10, 31);
        if (!day.isBefore(start) && !day.isAfter(end)) return y;
      }
      return years.last;
    }
  }
  return int.tryParse(parts.first.trim()) ?? today.year;
}

/// Column keys (`studentId-YYYY-MM-DD`) a stored attendance instant should light.
Set<String> attendanceRegisterKeysForRow(int studentId, DateTime storedDate) {
  return {
    for (final stamp in attendanceDateStamps(storedDate)) '$studentId-$stamp',
  };
}

/// Local calendar day (year/month/day) for [date].
DateTime attendanceCalendarDay(DateTime date) {
  final local = date.toLocal();
  return DateTime(local.year, local.month, local.day);
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

/// Inclusive named closed/holiday range for one attendance mode.
class AttendanceHolidayRange {
  const AttendanceHolidayRange({
    required this.name,
    required this.start,
    required this.end,
  });

  final String name;
  final DateTime start;
  final DateTime end;

  bool contains(DateTime date) {
    final day = attendanceCalendarDay(date);
    final from = attendanceCalendarDay(start);
    final to = attendanceCalendarDay(end);
    return !day.isBefore(from) && !day.isAfter(to);
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'start': attendanceIsoDate(start),
        'end': attendanceIsoDate(end),
      };

  static AttendanceHolidayRange? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final name = (raw['name'] ?? '').toString().trim();
    final start = parseAttendanceIsoDate(raw['start']?.toString());
    final end = parseAttendanceIsoDate(raw['end']?.toString());
    if (name.isEmpty || start == null || end == null) return null;
    if (end.isBefore(start)) {
      return AttendanceHolidayRange(name: name, start: end, end: start);
    }
    return AttendanceHolidayRange(name: name, start: start, end: end);
  }
}

/// Full-time and Hybrid closed/holiday ranges stored in app_settings.
class AttendanceHolidaysByMode {
  const AttendanceHolidaysByMode({
    required this.fullTime,
    required this.hybrid,
  });

  final List<AttendanceHolidayRange> fullTime;
  final List<AttendanceHolidayRange> hybrid;

  static const AttendanceHolidaysByMode empty = AttendanceHolidaysByMode(
    fullTime: [],
    hybrid: [],
  );

  /// 2026 Cape Town Full-time and Hybrid closed periods and public holidays.
  static AttendanceHolidaysByMode get seed2026 {
    AttendanceHolidayRange range(
      String name,
      int y1,
      int m1,
      int d1, [
      int? y2,
      int? m2,
      int? d2,
    ]) {
      return AttendanceHolidayRange(
        name: name,
        start: DateTime(y1, m1, d1),
        end: DateTime(y2 ?? y1, m2 ?? m1, d2 ?? d1),
      );
    }

    return AttendanceHolidaysByMode(
      fullTime: [
        range('Before college opens', 2026, 2, 1),
        range('Human Rights Day', 2026, 3, 21),
        range('Autumn break', 2026, 3, 28, 2026, 4, 7),
        range('Good Friday', 2026, 4, 3),
        range('Family Day', 2026, 4, 6),
        range("Workers' Day", 2026, 5, 1),
        range('Public holiday', 2026, 6, 15),
        range('Youth Day', 2026, 6, 16),
        range('Winter break', 2026, 6, 27, 2026, 7, 20),
        range("Women's Day", 2026, 8, 9),
        range('Public holiday', 2026, 8, 10),
        range('Heritage Day / Spring break', 2026, 9, 24, 2026, 10, 5),
        range('College closed', 2026, 10, 31),
      ],
      hybrid: [
        range('Before Hybrid opens', 2026, 2, 1, 2026, 2, 13),
        range('Winter gap', 2026, 6, 21, 2026, 7, 31),
        range('After last Hybrid class', 2026, 10, 25, 2026, 10, 31),
      ],
    );
  }

  List<AttendanceHolidayRange> forMode(String? mode) {
    final isHybrid = mode != null && mode.trim().toLowerCase() == 'hybrid';
    return isHybrid ? hybrid : fullTime;
  }

  AttendanceHolidaysByMode copyWith({
    List<AttendanceHolidayRange>? fullTime,
    List<AttendanceHolidayRange>? hybrid,
  }) {
    return AttendanceHolidaysByMode(
      fullTime: fullTime ?? this.fullTime,
      hybrid: hybrid ?? this.hybrid,
    );
  }

  String toJsonString() => jsonEncode({
        'fullTime': [for (final r in fullTime) r.toJson()],
        'hybrid': [for (final r in hybrid) r.toJson()],
      });

  static AttendanceHolidaysByMode fromJsonString(String? value) {
    if (value == null || value.trim().isEmpty) return empty;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map) return empty;
      return AttendanceHolidaysByMode(
        fullTime: _parseRanges(decoded['fullTime']),
        hybrid: _parseRanges(decoded['hybrid']),
      );
    } catch (_) {
      return empty;
    }
  }

  static List<AttendanceHolidayRange> _parseRanges(Object? raw) {
    if (raw is! List) return const [];
    final ranges = <AttendanceHolidayRange>[];
    for (final item in raw) {
      final range = AttendanceHolidayRange.tryParse(item);
      if (range != null) ranges.add(range);
    }
    return ranges;
  }
}

String attendanceIsoDate(DateTime date) {
  final day = attendanceCalendarDay(date);
  final y = day.year.toString().padLeft(4, '0');
  final m = day.month.toString().padLeft(2, '0');
  final d = day.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

DateTime? parseAttendanceIsoDate(String? value) {
  if (value == null) return null;
  final parts = value.trim().split('-');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  return DateTime(y, m, d);
}

bool isAttendanceHoliday(
  DateTime date,
  Iterable<AttendanceHolidayRange> holidays,
) {
  return holidays.any((range) => range.contains(date));
}

/// Whether [date] is a school day for this student cohort.
///
/// Sunday is never a school day.
/// Hybrid: Saturday only.
/// Full-time Year 3: Monday–Thursday.
/// Other Full-time: Monday–Friday.
/// Dates inside [holidays] for that mode are never school days.
bool isAttendanceSchoolDay({
  required DateTime date,
  required String? mode,
  required bool isYear3,
  Iterable<AttendanceHolidayRange> holidays = const [],
}) {
  final weekday = date.weekday;
  if (weekday == DateTime.sunday) return false;
  final isHybrid = mode != null && mode.trim().toLowerCase() == 'hybrid';
  final weekdayOk = isHybrid
      ? weekday == DateTime.saturday
      : isYear3
          ? weekday >= DateTime.monday && weekday <= DateTime.thursday
          : weekday >= DateTime.monday && weekday <= DateTime.friday;
  if (!weekdayOk) return false;
  return !isAttendanceHoliday(date, holidays);
}

/// Days from [days] that are a school day for at least one [students] cohort.
List<DateTime> filterAttendanceRegisterDays(
  Iterable<DateTime> days, {
  required Iterable<({String? mode, bool isYear3})> students,
  AttendanceHolidaysByMode holidays = AttendanceHolidaysByMode.empty,
}) {
  return [
    for (final date in days)
      if (students.any(
        (s) => isAttendanceSchoolDay(
          date: date,
          mode: s.mode,
          isYear3: s.isYear3,
          holidays: holidays.forMode(s.mode),
        ),
      ))
        date,
  ];
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
