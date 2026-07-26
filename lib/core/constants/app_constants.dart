/// Application-wide constants
class AppConstants {
  AppConstants._();

  // Test passing score
  static const int passingTestScore = 70;

  // Ministry hours requirements (post-MVP) – keys match UI: Full-time -> 'FullTime', Hybrid -> 'Hybrid'
  static const Map<String, Map<int, int>> ministryHoursRequirements = {
    'FullTime': {
      1: 15, // 1st year
      2: 7, // 2nd year
      3: 5, // 3rd year
    },
    'Hybrid': {
      1: 6, // 1st year
      2: 4, // 2nd year
      3: 2, // 3rd year
    },
  };

  /// Display string for ministry hours rule (3 terms per session).
  /// [modeUi] is the UI label e.g. "Full-time" or "Hybrid"; [yearLevel] is 1, 2, or 3.
  static String ministryHoursRequirementText(String modeUi, int yearLevel) {
    final key = modeUi == 'Full-time' ? 'FullTime' : 'Hybrid';
    final hours = ministryHoursRequirements[key]?[yearLevel] ?? 0;
    return '$hours HOURS PER TERM (1st, 2nd & 3rd term) ON OR OFF CAMPUS';
  }

  /// Ministry type options for dropdown (from design)
  static const List<String> ministryTypeOptions = [
    'Community Service',
    'Evangelism',
    'Teaching',
    'Worship',
    'Pastoral Care',
  ];

  /// Class options for report filters (Export & Reports screen).
  static const List<String> reportClassOptions = [
    'Year 1',
    'Year 2',
    'Year 3',
  ];

  /// Mission mode options for dropdown (Full-time, Hybrid, Both).
  static const List<String> missionModeOptions = [
    'Full-time',
    'Hybrid',
    'Both',
  ];

  // --- Dashboard finance KPIs (managerial diagnostics) ---

  /// Age buckets for arrears breakdown: days overdue (0–30, 31–60, 61–90, 90+).
  static const List<String> dashboardArrearsBucketLabels = [
    '0–30 days',
    '31–60 days',
    '61–90 days',
    '90+ days',
  ];

  /// Monthly balance due above this amount (Rand) triggers risk highlighting.
  static const double dashboardBalanceDueAlertThreshold = 50000.0;

  /// When 90+ days bucket exceeds this fraction (0.0–1.0) of total balance due, show risk cue.
  static const double dashboardArrears90PercentAlertThreshold = 0.25;

  // --- Attendance expected-day thresholds (placeholders; tune with client) ---

  /// Expected present days in a calendar month (placeholder).
  static const int attendanceExpectedDaysPerMonth = 16;

  /// Expected present days in one academic term (placeholder).
  static const int attendanceExpectedDaysPerTerm = 48;

  /// Expected present days in a full academic session / year (placeholder).
  static const int attendanceExpectedDaysPerYear = 144;
}
