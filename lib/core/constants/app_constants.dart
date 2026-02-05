/// Application-wide constants
class AppConstants {
  AppConstants._();

  // Tuition
  static const double fullTuitionAmount = 19800.0; // Rand
  static const double lumpSumDiscountAmount = 18000.0; // Rand

  // Test passing score
  static const int passingTestScore = 70;

  // Ministry hours requirements (post-MVP)
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
}
