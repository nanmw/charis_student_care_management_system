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

  group('attendanceDateStamps', () {
    test('UTC midnight includes that calendar day', () {
      expect(
        attendanceDateStamps(DateTime.utc(2026, 7, 15)),
        contains('2026-07-15'),
      );
    });

    test('UTC evening of previous day also stamps the next calendar day', () {
      expect(
        attendanceDateStamps(DateTime.utc(2026, 7, 14, 22)),
        contains('2026-07-15'),
      );
    });

    test('local midnight DateTime stamps that local day', () {
      expect(
        attendanceDateStamps(DateTime(2026, 7, 15)),
        contains('2026-07-15'),
      );
    });

    test('attendanceDayInRange keeps UTC-evening encoding inside Term 2', () {
      expect(
        attendanceDayInRange(
          DateTime.utc(2026, 7, 14, 22),
          DateTime(2026, 5, 1),
          DateTime(2026, 7, 31),
        ),
        isTrue,
      );
    });
  });

  group('sessionCalendarYear', () {
    test('single-year 2026 stays 2026', () {
      expect(
        sessionCalendarYear(
          sessionCode: '2026',
          now: DateTime(2026, 8, 25),
        ),
        2026,
      );
    });

    test('2025-2026 in August 2026 is 2026', () {
      expect(
        sessionCalendarYear(
          sessionCode: '2025-2026',
          now: DateTime(2026, 8, 25),
        ),
        2026,
      );
    });

    test('prefers startDate year over code', () {
      expect(
        sessionCalendarYear(
          sessionCode: '2025-2026',
          startDate: DateTime.utc(2026, 2, 1),
          now: DateTime(2026, 8, 25),
        ),
        2026,
      );
    });
  });

  group('attendanceRegisterKeysForRow', () {
    test('UTC evening lights the next calendar-day column', () {
      final keys = attendanceRegisterKeysForRow(
        1,
        DateTime.utc(2026, 7, 14, 22),
      );
      expect(keys, contains('1-2026-07-15'));
    });

    test('May UTC midnight still lights May', () {
      final keys = attendanceRegisterKeysForRow(
        1,
        DateTime.utc(2026, 5, 12),
      );
      expect(keys, contains('1-2026-05-12'));
    });
  });

  group('isAttendanceSchoolDay', () {
    final saturday = DateTime(2026, 8, 22);
    final sunday = DateTime(2026, 8, 23);
    final monday = DateTime(2026, 8, 24);
    final thursday = DateTime(2026, 8, 20);
    final friday = DateTime(2026, 8, 21);

    test('Sunday is never a school day', () {
      expect(
        isAttendanceSchoolDay(date: sunday, mode: 'Full-time', isYear3: false),
        isFalse,
      );
      expect(
        isAttendanceSchoolDay(date: sunday, mode: 'Full-time', isYear3: true),
        isFalse,
      );
      expect(
        isAttendanceSchoolDay(date: sunday, mode: 'Hybrid', isYear3: false),
        isFalse,
      );
    });

    test('Hybrid is Saturday only', () {
      expect(
        isAttendanceSchoolDay(date: saturday, mode: 'Hybrid', isYear3: false),
        isTrue,
      );
      expect(
        isAttendanceSchoolDay(date: monday, mode: 'hybrid', isYear3: false),
        isFalse,
      );
      expect(
        isAttendanceSchoolDay(date: friday, mode: 'Hybrid', isYear3: true),
        isFalse,
      );
    });

    test('Full-time Friday vs Saturday', () {
      expect(
        isAttendanceSchoolDay(date: friday, mode: 'Full-time', isYear3: false),
        isTrue,
      );
      expect(
        isAttendanceSchoolDay(date: saturday, mode: 'Full-time', isYear3: false),
        isFalse,
      );
    });

    test('Year 3 Full-time is Monday–Thursday', () {
      expect(
        isAttendanceSchoolDay(date: thursday, mode: 'Full-time', isYear3: true),
        isTrue,
      );
      expect(
        isAttendanceSchoolDay(date: friday, mode: 'Full-time', isYear3: true),
        isFalse,
      );
      expect(
        isAttendanceSchoolDay(date: monday, mode: 'Full-time', isYear3: true),
        isTrue,
      );
    });
  });

  group('filterAttendanceRegisterDays', () {
    final week = [
      DateTime(2026, 8, 21), // Friday
      DateTime(2026, 8, 22), // Saturday
      DateTime(2026, 8, 23), // Sunday
      DateTime(2026, 8, 24), // Monday
    ];

    test('Sunday is always dropped', () {
      final days = filterAttendanceRegisterDays(
        week,
        students: const [
          (mode: 'Full-time', isYear3: false),
          (mode: 'Hybrid', isYear3: false),
        ],
      );
      expect(days.any((d) => d.weekday == DateTime.sunday), isFalse);
    });

    test('Hybrid keeps only Saturday', () {
      final days = filterAttendanceRegisterDays(
        week,
        students: const [(mode: 'Hybrid', isYear3: false)],
      );
      expect(days, [DateTime(2026, 8, 22)]);
    });

    test('Full-time mixed keeps Friday', () {
      final days = filterAttendanceRegisterDays(
        week,
        students: const [
          (mode: 'Full-time', isYear3: true),
          (mode: 'Full-time', isYear3: false),
        ],
      );
      expect(days, [DateTime(2026, 8, 21), DateTime(2026, 8, 24)]);
    });

    test('Year 3-only drops Friday', () {
      final days = filterAttendanceRegisterDays(
        week,
        students: const [(mode: 'Full-time', isYear3: true)],
      );
      expect(days, [DateTime(2026, 8, 24)]);
    });
  });

  group('2026 attendance holidays', () {
    final seed = AttendanceHolidaysByMode.seed2026;

    test('Full-time 15 Jul 2026 is not a school day', () {
      expect(
        isAttendanceSchoolDay(
          date: DateTime(2026, 7, 15),
          mode: 'Full-time',
          isYear3: false,
          holidays: seed.fullTime,
        ),
        isFalse,
      );
    });

    test('Full-time 8 Apr 2026 (Term 2 open) is a school day', () {
      expect(
        isAttendanceSchoolDay(
          date: DateTime(2026, 4, 8),
          mode: 'Full-time',
          isYear3: false,
          holidays: seed.fullTime,
        ),
        isTrue,
      );
    });

    test('Hybrid 4 Jul 2026 Saturday is not a school day', () {
      expect(
        isAttendanceSchoolDay(
          date: DateTime(2026, 7, 4),
          mode: 'Hybrid',
          isYear3: false,
          holidays: seed.hybrid,
        ),
        isFalse,
      );
    });

    test('Hybrid 1 Aug 2026 Saturday is a school day', () {
      expect(
        isAttendanceSchoolDay(
          date: DateTime(2026, 8, 1),
          mode: 'Hybrid',
          isYear3: false,
          holidays: seed.hybrid,
        ),
        isTrue,
      );
    });

    test('21 Mar 2026 Full-time is not (Human Rights Day)', () {
      expect(
        isAttendanceSchoolDay(
          date: DateTime(2026, 3, 21),
          mode: 'Full-time',
          isYear3: false,
          holidays: seed.fullTime,
        ),
        isFalse,
      );
    });

    test('Year 3 Hybrid 31 Jan 2026 Saturday stays a school day', () {
      expect(
        isAttendanceSchoolDay(
          date: DateTime(2026, 1, 31),
          mode: 'Hybrid',
          isYear3: true,
          holidays: seed.hybrid,
        ),
        isTrue,
      );
    });
  });
}
