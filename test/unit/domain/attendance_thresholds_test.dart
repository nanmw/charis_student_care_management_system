import 'package:flutter_test/flutter_test.dart';

import 'package:charis_student_care/core/constants/app_constants.dart';
import 'package:charis_student_care/domain/attendance/attendance_thresholds.dart';

void main() {
  group('attendance thresholds', () {
    test('evaluateAttendanceThreshold computes shortfall', () {
      final r = evaluateAttendanceThreshold(
        period: AttendanceThresholdPeriod.month,
        presentDays: 10,
      );
      expect(r.expectedDays, AppConstants.attendanceExpectedDaysPerMonth);
      expect(r.shortfall, AppConstants.attendanceExpectedDaysPerMonth - 10);
      expect(r.met, isFalse);
    });

    test('met when presentDays >= expected', () {
      final r = evaluateAttendanceThreshold(
        period: AttendanceThresholdPeriod.month,
        presentDays: AppConstants.attendanceExpectedDaysPerMonth,
      );
      expect(r.met, isTrue);
      expect(r.shortfall, 0);
    });

    test('explicit expectedDays override wins over defaults', () {
      final r = evaluateAttendanceThreshold(
        period: AttendanceThresholdPeriod.month,
        presentDays: 12,
        expectedDays: 20,
      );
      expect(r.expectedDays, 20);
      expect(r.shortfall, 8);
      expect(r.met, isFalse);
    });

    test('config override wins over AppConstants defaults', () {
      const config = AttendanceThresholdConfig(month: 20, term: 60, year: 180);
      final r = evaluateAttendanceThreshold(
        period: AttendanceThresholdPeriod.term,
        presentDays: 55,
        config: config,
      );
      expect(r.expectedDays, 60);
      expect(r.shortfall, 5);
    });

    test('term date ranges cover Feb–Oct terms', () {
      final t1 = termDateRange(2026, 1);
      expect(t1.$1, DateTime(2026, 2, 1));
      expect(t1.$2, DateTime(2026, 4, 30));
      final t3 = termDateRange(2026, 3);
      expect(t3.$1, DateTime(2026, 8, 1));
    });

    test('termNumberForMonth maps to T1/T2/T3', () {
      expect(termNumberForMonth(2), 1);
      expect(termNumberForMonth(4), 1);
      expect(termNumberForMonth(5), 2);
      expect(termNumberForMonth(7), 2);
      expect(termNumberForMonth(8), 3);
      expect(termNumberForMonth(12), 3);
    });

    test('calendarDaysInRange enumerates inclusive term days', () {
      final t1 = termDateRange(2026, 1);
      final days = calendarDaysInRange(t1.$1, t1.$2);
      expect(days.length, 89); // Feb 28 + Mar 31 + Apr 30 (non-leap)
      expect(days.first, DateTime(2026, 2, 1));
      expect(days.last, DateTime(2026, 4, 30));
    });

    test('calendarDaysInRange includes leap day', () {
      final days = calendarDaysInRange(
        DateTime(2024, 2, 1),
        DateTime(2024, 2, 29),
      );
      expect(days.length, 29);
      expect(days.last, DateTime(2024, 2, 29));
    });

    test('register percent uses expected term days not calendar column count', () {
      final t1 = termDateRange(2026, 1);
      final calendarCount = calendarDaysInRange(t1.$1, t1.$2).length;
      const presentDays = 16;
      final r = evaluateAttendanceThreshold(
        period: AttendanceThresholdPeriod.term,
        presentDays: presentDays,
      );
      expect(r.expectedDays, AppConstants.attendanceExpectedDaysPerTerm);
      expect(calendarCount, greaterThan(r.expectedDays));
      expect(
        r.percentOfExpected,
        closeTo(presentDays / r.expectedDays * 100, 0.01),
      );
      expect(
        r.percentOfExpected,
        isNot(closeTo(presentDays / calendarCount * 100, 0.01)),
      );
    });

    test('hybrid defaults are 2 / 6 / 18', () {
      expect(
        AttendanceThresholdConfig.hybridDefaults.month,
        AppConstants.attendanceExpectedDaysHybridPerMonth,
      );
      expect(AttendanceThresholdConfig.hybridDefaults.month, 2);
      expect(AttendanceThresholdConfig.hybridDefaults.term, 6);
      expect(AttendanceThresholdConfig.hybridDefaults.year, 18);
      expect(AttendanceThresholdConfig.defaults.month, 16);
      expect(AttendanceThresholdConfig.defaults.term, 48);
      expect(AttendanceThresholdConfig.defaults.year, 144);
    });

    test('forMode selects hybrid vs full-time', () {
      const byMode = AttendanceThresholdsByMode.defaults;
      expect(byMode.forMode('Hybrid').term, 6);
      expect(byMode.forMode('hybrid').term, 6);
      expect(byMode.forMode('Full-time').term, 48);
      expect(byMode.forMode(null).term, 48);
      expect(byMode.forMode('').term, 48);
    });

    test('hybrid register percent uses term expected days not calendar count', () {
      final t1 = termDateRange(2026, 1);
      final calendarCount = calendarDaysInRange(t1.$1, t1.$2).length;
      const presentDays = 4;
      final r = evaluateAttendanceThreshold(
        period: AttendanceThresholdPeriod.term,
        presentDays: presentDays,
        config: AttendanceThresholdConfig.hybridDefaults,
      );
      expect(r.expectedDays, AppConstants.attendanceExpectedDaysHybridPerTerm);
      expect(calendarCount, greaterThan(r.expectedDays));
      expect(
        r.percentOfExpected,
        closeTo(presentDays / r.expectedDays * 100, 0.01),
      );
    });
  });
}
