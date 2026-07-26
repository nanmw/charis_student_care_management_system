import 'package:flutter_test/flutter_test.dart';

import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/domain/finance/session_payment_math.dart';

Payment _payment({
  required int studentId,
  required String year,
  double jan = 0,
  double feb = 0,
  double mar = 0,
  double lumpSum = 0,
  double nov = 0,
}) {
  final now = DateTime(2026, 1, 1);
  return Payment(
    id: 1,
    studentId: studentId,
    year: year,
    jan: jan,
    feb: feb,
    mar: mar,
    apr: 0,
    may: 0,
    jun: 0,
    jul: 0,
    aug: 0,
    sep: 0,
    oct: 0,
    nov: nov,
    dec: 0,
    lumpSum: lumpSum,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('sessionMonthsForCode', () {
    test('single-year code returns Feb–Oct', () {
      final months = sessionMonthsForCode('2026');
      expect(months.length, 9);
      expect(months.first, (2026, 2));
      expect(months.last, (2026, 10));
    });

    test('legacy code uses start year', () {
      final months = sessionMonthsForCode('2025-2026');
      expect(months.first.$1, 2025);
      expect(months.length, 9);
    });
  });

  group('sessionPaymentTotal', () {
    test('includes lumpSum and excludes jan/nov/dec', () {
      final p = _payment(
        studentId: 1,
        year: '2026',
        jan: 200,
        feb: 100,
        mar: 50,
        lumpSum: 500,
        nov: 999,
      );
      // feb+mar+...+oct(0)+lumpSum; jan/nov/dec not in formula
      expect(sessionPaymentTotal(p), 650);
    });

    test('jan alone does not count toward session total', () {
      final p = _payment(studentId: 1, year: '2026', jan: 1000);
      expect(sessionPaymentTotal(p), 0);
    });
  });

  group('paidPriorIncludingLumpSum', () {
    test('counts monthly prior amounts plus lumpSum once', () {
      final p = _payment(studentId: 1, year: '2026', feb: 100, mar: 100, lumpSum: 1000);
      final byStudentYear = <(int, int), Payment>{(1, 2026): p};
      final sessionMonths = sessionMonthsForCode('2026');
      // numMonthsBefore = 2 => Feb + Mar + lumpSum
      final paid = paidPriorIncludingLumpSum(
        studentId: 1,
        sessionMonths: sessionMonths,
        numMonthsBefore: 2,
        byStudentYear: byStudentYear,
      );
      expect(paid, 1200);
    });
  });

  group('totalSessionPaidForStudent', () {
    test('sums all rows for the student', () {
      final a = _payment(studentId: 1, year: '2026', feb: 100, lumpSum: 50);
      final b = _payment(studentId: 1, year: '2025', feb: 20);
      final other = _payment(studentId: 2, year: '2026', feb: 999);
      expect(totalSessionPaidForStudent([a, b, other], 1), 170);
    });
  });

  group('paymentBelongsToSession', () {
    test('matches single-year and legacy start year', () {
      final p = _payment(studentId: 1, year: '2026');
      expect(paymentBelongsToSession(p, '2026'), isTrue);
      expect(paymentBelongsToSession(p, '2026-2027'), isTrue);
      expect(paymentBelongsToSession(p, '2025'), isFalse);
    });
  });
}
