import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/academic_session_repository.dart';

/// Session months: Feb–Oct of the session year.
/// Single-year code "2026" -> [(2026,2), ..., (2026,10)].
/// Legacy "YYYY-YYYY" is treated as start year -> Feb–Oct of that year.
List<(int year, int month)> sessionMonthsForCode(String sessionCode) {
  final trimmed = sessionCode.trim();
  final parts = trimmed.split('-');
  final year = int.tryParse(parts.first.trim());
  if (year == null) return [];
  final list = <(int, int)>[];
  for (var m = 2; m <= 10; m++) {
    list.add((year, m));
  }
  return list;
}

/// Amount paid in a given calendar (year, month) from a [Payment] row
/// (row must be for that year).
double paymentAmountForMonth(Payment p, int year, int month) {
  if (p.year != year.toString()) return 0.0;
  switch (month) {
    case 1:
      return p.jan;
    case 2:
      return p.feb;
    case 3:
      return p.mar;
    case 4:
      return p.apr;
    case 5:
      return p.may;
    case 6:
      return p.jun;
    case 7:
      return p.jul;
    case 8:
      return p.aug;
    case 9:
      return p.sep;
    case 10:
      return p.oct;
    case 11:
      return p.nov;
    case 12:
      return p.dec;
    default:
      return 0.0;
  }
}

/// True when calendar [year]/[month] overlaps [[rangeStart], [rangeEnd]] (inclusive).
bool calendarMonthOverlapsRange({
  required int year,
  required int month,
  required DateTime rangeStart,
  required DateTime rangeEnd,
}) {
  if (month < 1 || month > 12) return false;
  final monthStart = DateTime.utc(year, month, 1);
  final monthEnd = month == 12
      ? DateTime.utc(year, 12, 31, 23, 59, 59, 999)
      : DateTime.utc(year, month + 1, 1)
          .subtract(const Duration(milliseconds: 1));
  final start = DateTime.utc(rangeStart.year, rangeStart.month, rangeStart.day);
  final end = DateTime.utc(
    rangeEnd.year,
    rangeEnd.month,
    rangeEnd.day,
    23,
    59,
    59,
    999,
  );
  return !monthEnd.isBefore(start) && !monthStart.isAfter(end);
}

/// True when calendar [year] (1 Jan–31 Dec) overlaps the date range.
bool calendarYearOverlapsRange(
  int year,
  DateTime rangeStart,
  DateTime rangeEnd,
) {
  final yearStart = DateTime.utc(year, 1, 1);
  final yearEnd = DateTime.utc(year, 12, 31, 23, 59, 59, 999);
  final start = DateTime.utc(rangeStart.year, rangeStart.month, rangeStart.day);
  final end = DateTime.utc(
    rangeEnd.year,
    rangeEnd.month,
    rangeEnd.day,
    23,
    59,
    59,
    999,
  );
  return !yearEnd.isBefore(start) && !yearStart.isAfter(end);
}

/// Sum of monthly amounts (and lump sum) whose calendar month overlaps [rangeStart]–[rangeEnd].
double paymentTotalInDateRange(
  Payment p,
  DateTime rangeStart,
  DateTime rangeEnd,
) {
  final year = int.tryParse(p.year);
  if (year == null) return 0;
  var total = 0.0;
  var yearOverlaps = false;
  for (var m = 1; m <= 12; m++) {
    if (calendarMonthOverlapsRange(
      year: year,
      month: m,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
    )) {
      yearOverlaps = true;
      total += paymentAmountForMonth(p, year, m);
    }
  }
  if (yearOverlaps) total += p.lumpSum;
  return total;
}

/// Session tuition paid on one payment row (Feb–Oct months + lump sum).
/// Jan/Nov/Dec are excluded (outside the academic session).
double sessionPaymentTotal(Payment p) {
  return p.feb +
      p.mar +
      p.apr +
      p.may +
      p.jun +
      p.jul +
      p.aug +
      p.sep +
      p.oct +
      p.lumpSum;
}

/// Sum of [sessionPaymentTotal] for all [payments] belonging to [studentId].
double totalSessionPaidForStudent(Iterable<Payment> payments, int studentId) {
  var total = 0.0;
  for (final p in payments) {
    if (p.studentId == studentId) {
      total += sessionPaymentTotal(p);
    }
  }
  return total;
}

/// Whether a payment row belongs to the given academic [sessionCode].
/// Matches calendar year derived from the session (single-year or legacy).
bool paymentBelongsToSession(Payment p, String sessionCode) {
  final year = AcademicSessionRepository.yearFromSessionCode(sessionCode);
  if (year == null) return false;
  return p.year == year;
}

/// Payments for [studentId] that belong to [sessionCode].
List<Payment> paymentsForStudentInSession(
  Iterable<Payment> payments,
  int studentId,
  String sessionCode,
) {
  return payments
      .where(
        (p) => p.studentId == studentId && paymentBelongsToSession(p, sessionCode),
      )
      .toList();
}

/// Paid amount counted toward balance brought forward (months before focus
/// plus any lump sum on those payment rows).
double paidPriorIncludingLumpSum({
  required int studentId,
  required List<(int year, int month)> sessionMonths,
  required int numMonthsBefore,
  required Map<(int studentId, int year), Payment> byStudentYear,
}) {
  var paidPrior = 0.0;
  final yearsSeen = <int>{};
  for (var i = 0; i < numMonthsBefore && i < sessionMonths.length; i++) {
    final (y, m) = sessionMonths[i];
    final p = byStudentYear[(studentId, y)];
    if (p != null) {
      paidPrior += paymentAmountForMonth(p, y, m);
      yearsSeen.add(y);
    }
  }
  for (final y in yearsSeen) {
    final p = byStudentYear[(studentId, y)];
    if (p != null) {
      paidPrior += p.lumpSum;
    }
  }
  return paidPrior;
}

/// Total paid across session months + lump sum for one student.
double sessionTotalPaidIncludingLumpSum({
  required int studentId,
  required List<(int year, int month)> sessionMonths,
  required Map<(int studentId, int year), Payment> byStudentYear,
}) {
  var totalPaid = 0.0;
  final yearsSeen = <int>{};
  for (final (y, m) in sessionMonths) {
    final p = byStudentYear[(studentId, y)];
    if (p != null) {
      totalPaid += paymentAmountForMonth(p, y, m);
      yearsSeen.add(y);
    }
  }
  for (final y in yearsSeen) {
    final p = byStudentYear[(studentId, y)];
    if (p != null) {
      totalPaid += p.lumpSum;
    }
  }
  // Also count lump sum on any session payment row not already covered
  // (e.g. only lump sum, no monthly amounts).
  for (final entry in byStudentYear.entries) {
    if (entry.key.$1 != studentId) continue;
    if (yearsSeen.contains(entry.key.$2)) continue;
    final sessionYears = sessionMonths.map((e) => e.$1).toSet();
    if (sessionYears.contains(entry.key.$2)) {
      totalPaid += entry.value.lumpSum;
    }
  }
  return totalPaid;
}
