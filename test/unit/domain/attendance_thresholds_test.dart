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
  });
}
