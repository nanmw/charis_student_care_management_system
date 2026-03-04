import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;

import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/academic_session_repository.dart';
import 'package:charis_student_care/data/repositories/payment_repository.dart';
import 'package:charis_student_care/data/repositories/mission_payment_repository.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.test();
  });

  tearDown(() async {
    await db.close();
  });

  group('PaymentRepository session filtering', () {
    test('watchPaymentsForSession returns rows with matching academic_session_id', () async {
      final sessionRepo = AcademicSessionRepository(db);
      final sessionId = await sessionRepo.getSessionIdByCode('2024-2025');
      expect(sessionId, isNotNull);

      final studentId = await db.into(db.students).insert(
            StudentsCompanion.insert(surname: 'Pay', firstName: 'Test'),
          );
      await db.into(db.payments).insert(
            PaymentsCompanion.insert(
              studentId: studentId,
              year: '2024',
              academicSessionId: Value(sessionId),
            ),
          );

      final paymentRepo = PaymentRepository(db);
      final list = await paymentRepo.watchPaymentsForSession('2024-2025').first;
      expect(list.length, equals(1));
      expect(list.first.studentId, equals(studentId));
      expect(list.first.academicSessionId, equals(sessionId));
    });

    test('watchPaymentsForSession includes legacy rows (null academic_session_id, matching year)', () async {
      final sessionRepo = AcademicSessionRepository(db);
      final sessionId = await sessionRepo.getSessionIdByCode('2024-2025');
      expect(sessionId, isNotNull);

      final studentWithFk = await db.into(db.students).insert(
            StudentsCompanion.insert(surname: 'WithFk', firstName: 'A'),
          );
      final studentLegacy = await db.into(db.students).insert(
            StudentsCompanion.insert(surname: 'Legacy', firstName: 'B'),
          );
      await db.into(db.payments).insert(
            PaymentsCompanion.insert(
              studentId: studentWithFk,
              year: '2024',
              academicSessionId: Value(sessionId),
            ),
          );
      await db.into(db.payments).insert(
            PaymentsCompanion.insert(
              studentId: studentLegacy,
              year: '2024',
              academicSessionId: const Value.absent(),
            ),
          );

      final paymentRepo = PaymentRepository(db);
      final list = await paymentRepo.watchPaymentsForSession('2024-2025').first;
      expect(list.length, equals(2));
      expect(list.any((p) => p.studentId == studentWithFk && p.academicSessionId == sessionId), isTrue);
      expect(list.any((p) => p.studentId == studentLegacy && p.academicSessionId == null && p.year == '2024'), isTrue);
    });
  });

  group('MissionPaymentRepository session filtering', () {
    test('watchForSession returns rows with matching academic_session_id', () async {
      final sessionRepo = AcademicSessionRepository(db);
      final sessionId = await sessionRepo.getSessionIdByCode('2024-2025');
      expect(sessionId, isNotNull);

      final studentId = await db.into(db.students).insert(
            StudentsCompanion.insert(surname: 'Mission', firstName: 'Test'),
          );
      await db.into(db.missionPaymentSchedule).insert(
            MissionPaymentScheduleCompanion.insert(
              studentId: studentId,
              year: '2024',
              academicSessionId: Value(sessionId),
            ),
          );

      final missionRepo = MissionPaymentRepository(db);
      final list = await missionRepo.watchForSession('2024-2025').first;
      expect(list.length, equals(1));
      expect(list.first.studentId, equals(studentId));
      expect(list.first.academicSessionId, equals(sessionId));
    });

    test('watchForSession includes legacy rows (null academic_session_id, matching year)', () async {
      final sessionRepo = AcademicSessionRepository(db);
      final sessionId = await sessionRepo.getSessionIdByCode('2024-2025');
      expect(sessionId, isNotNull);

      final studentWithFk = await db.into(db.students).insert(
            StudentsCompanion.insert(surname: 'MWithFk', firstName: 'A'),
          );
      final studentLegacy = await db.into(db.students).insert(
            StudentsCompanion.insert(surname: 'MLegacy', firstName: 'B'),
          );
      await db.into(db.missionPaymentSchedule).insert(
            MissionPaymentScheduleCompanion.insert(
              studentId: studentWithFk,
              year: '2024',
              academicSessionId: Value(sessionId),
            ),
          );
      await db.into(db.missionPaymentSchedule).insert(
            MissionPaymentScheduleCompanion.insert(
              studentId: studentLegacy,
              year: '2024',
              academicSessionId: const Value.absent(),
            ),
          );

      final missionRepo = MissionPaymentRepository(db);
      final list = await missionRepo.watchForSession('2024-2025').first;
      expect(list.length, equals(2));
      expect(list.any((r) => r.studentId == studentWithFk && r.academicSessionId == sessionId), isTrue);
      expect(list.any((r) => r.studentId == studentLegacy && r.academicSessionId == null && r.year == '2024'), isTrue);
    });
  });

  group('AcademicSessionRepository helpers', () {
    test('yearFromSessionCode returns start year for code', () {
      expect(AcademicSessionRepository.yearFromSessionCode('2024-2025'), equals('2024'));
      expect(AcademicSessionRepository.yearFromSessionCode('2025-2026'), equals('2025'));
      expect(AcademicSessionRepository.yearFromSessionCode(null), isNull);
      expect(AcademicSessionRepository.yearFromSessionCode(''), isNull);
    });
  });
}
