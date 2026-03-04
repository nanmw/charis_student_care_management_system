/// Application-wide constants
class AppConstants {
  AppConstants._();

  // Tuition
  static const double fullTuitionAmount = 19800.0; // Rand
  static const double lumpSumDiscountAmount = 18000.0; // Rand

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

  /// Display string for ministry hours rule (e.g. "7 HOURS PER TERM (1st & 2nd term) ON OR OFF CAMPUS").
  /// [modeUi] is the UI label e.g. "Full-time" or "Hybrid"; [yearLevel] is 1, 2, or 3.
  static String ministryHoursRequirementText(String modeUi, int yearLevel) {
    final key = modeUi == 'Full-time' ? 'FullTime' : 'Hybrid';
    final hours = ministryHoursRequirements[key]?[yearLevel] ?? 0;
    return '$hours HOURS PER TERM (1st & 2nd term) ON OR OFF CAMPUS';
  }

  /// Ministry type options for dropdown (from design)
  static const List<String> ministryTypeOptions = [
    'Community Service',
    'Evangelism',
    'Teaching',
    'Worship',
    'Pastoral Care',
  ];

  /// Year options for report filters (legacy / single-student export).
  static const List<String> reportYearOptions = [
    '2024',
    '2025',
    '2026',
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

  /// Year filter options for missions (e.g. filter by year).
  static const List<String> missionYearFilterOptions = [
    '2024',
    '2025',
    '2026',
    '2027',
  ];
}
