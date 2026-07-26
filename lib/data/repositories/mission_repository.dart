import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:charis_student_care/core/config/sync_folder_config.dart';
import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/database/tables/mission_participations.dart';
import 'package:charis_student_care/data/database/tables/missions.dart';
import 'package:charis_student_care/data/database/tables/students.dart';
import 'package:charis_student_care/data/repositories/class_repository.dart';

/// Valid mission mode values (required when creating/updating missions).
const List<String> missionModeValues = ['Full-time', 'Hybrid', 'Both'];

/// Row type from Drift select().join() (has readTable).
typedef JoinedRow = dynamic;

/// Joined row for mission participation table: participation + student + mission + payment summary.
class MissionParticipationRow {
  const MissionParticipationRow({
    required this.participation,
    required this.student,
    required this.mission,
    required this.paidToDate,
    required this.balance,
  });

  final MissionParticipation participation;
  final Student student;
  final Mission mission;

  /// Sum of all payments toward this participation.
  final double paidToDate;

  /// participation.amount - paidToDate
  final double balance;
}

/// Mission repository: missions and participations with optional change-set logging.
/// Only Admin Level 01 can manage missions (create/edit/deactivate).
class MissionRepository {
  MissionRepository(
    this._db, {
    ClassRepository? classRepo,
    void Function()? onLocalChangeSetWritten,
  })  : _classRepo = classRepo ?? ClassRepository(_db),
        _onLocalChangeSetWritten = onLocalChangeSetWritten;

  final AppDatabase _db;
  final ClassRepository _classRepo;
  final void Function()? _onLocalChangeSetWritten;
  static const _uuid = Uuid();

  Future<String> _effectiveChangeSetDeviceId(String? deviceId) async {
    final d = deviceId?.trim();
    if (d != null && d.isNotEmpty && d != 'legacy') return d;
    return SyncFolderConfig.getOrCreateDeviceId();
  }

  // --- Missions

  /// Stream of missions filtered by [year] (null = all) and [activeOnly].
  Stream<List<Mission>> watchMissions({
    String? year,
    bool activeOnly = true,
  }) {
    var query = _db.select(_db.missions)
      ..orderBy([(t) => OrderingTerm.desc(t.startDate)]);
    if (year != null && year.isNotEmpty) {
      query = query..where((t) => t.year.equals(year));
    }
    if (activeOnly) {
      query = query..where((t) => t.isActive.equals(true));
    }
    return query.watch();
  }

  /// Fetch a single mission by id, or null if not found.
  Future<Mission?> getMission(int id) async {
    return (_db.select(_db.missions)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// Adds a mission. Requires Admin Level 01. [mode] is required.
  /// [userId], [userDisplayName], [screen] used for change-set if provided.
  Future<int> addMission({
    required String title,
    required String location,
    required DateTime startDate,
    required DateTime endDate,
    required int slotsTotal,
    String? description,
    bool isActive = true,
    required String year,
    required String mode,
    double? amount,
    required UserRole userRole,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    if (!RolePermissions.canManageMissions(userRole)) {
      throw StateError('Role cannot manage missions');
    }
    final m = mode.trim();
    if (!missionModeValues.contains(m)) {
      throw ArgumentError(
          'Mode must be one of: ${missionModeValues.join(", ")}',);
    }
    final t = title.trim();
    if (t.isEmpty) throw ArgumentError('Mission title cannot be empty');
    if (slotsTotal < 1) throw ArgumentError('Slots total must be at least 1');
    if (endDate.isBefore(startDate)) {
      throw ArgumentError('End date must be on or after start date');
    }
    final companion = MissionsCompanion.insert(
      title: t,
      location: location.trim(),
      startDate: startDate,
      endDate: endDate,
      slotsTotal: slotsTotal,
      description: Value(
          description?.trim().isEmpty ?? true ? null : description?.trim(),),
      isActive: Value(isActive),
      year: year,
      mode: m,
      amount: Value(amount),
    );
    final id = await _db.into(_db.missions).insert(companion);
    if (userId != null) {
      final desc =
          description?.trim().isEmpty ?? true ? null : description?.trim();
      await _insertChangeSet(
        table: 'missions',
        recordId: id.toString(),
        operation: 'INSERT',
        payload: {
          'title': t,
          'location': location.trim(),
          'startDate': startDate.toIso8601String(),
          'endDate': endDate.toIso8601String(),
          'slotsTotal': slotsTotal,
          if (desc != null) 'description': desc,
          'isActive': isActive,
          'year': year,
          'mode': m,
          if (amount != null) 'amount': amount,
          'academicSession': year,
        },
        userId: userId,
        version: 1,
        deviceId: deviceId,
        userDisplayName: userDisplayName,
        screen: screen,
      );
    }
    return id;
  }

  /// Updates a mission. Requires Admin Level 01. [mode] is required.
  /// [userId], [userDisplayName], [screen] used for change-set if provided.
  Future<void> updateMission(
    int id, {
    required String title,
    required String location,
    required DateTime startDate,
    required DateTime endDate,
    required int slotsTotal,
    String? description,
    required bool isActive,
    required String year,
    required String mode,
    double? amount,
    required UserRole userRole,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    if (!RolePermissions.canManageMissions(userRole)) {
      throw StateError('Role cannot manage missions');
    }
    final m = mode.trim();
    if (!missionModeValues.contains(m)) {
      throw ArgumentError(
          'Mode must be one of: ${missionModeValues.join(", ")}',);
    }
    final row = await getMission(id);
    if (row == null) throw StateError('Mission not found');
    final t = title.trim();
    if (t.isEmpty) throw ArgumentError('Mission title cannot be empty');
    if (slotsTotal < 1) throw ArgumentError('Slots total must be at least 1');
    if (endDate.isBefore(startDate)) {
      throw ArgumentError('End date must be on or after start date');
    }
    await (_db.update(_db.missions)..where((t) => t.id.equals(id))).write(
      MissionsCompanion(
        title: Value(t),
        location: Value(location.trim()),
        startDate: Value(startDate),
        endDate: Value(endDate),
        slotsTotal: Value(slotsTotal),
        description: Value(
            description?.trim().isEmpty ?? true ? null : description?.trim(),),
        isActive: Value(isActive),
        year: Value(year),
        mode: Value(m),
        amount: Value(amount),
        updatedAt: Value(DateTime.now()),
      ),
    );
    if (userId != null) {
      final desc =
          description?.trim().isEmpty ?? true ? null : description?.trim();
      await _insertChangeSet(
        table: 'missions',
        recordId: id.toString(),
        operation: 'UPDATE',
        payload: {
          'title': t,
          'location': location.trim(),
          'startDate': startDate.toIso8601String(),
          'endDate': endDate.toIso8601String(),
          'slotsTotal': slotsTotal,
          if (desc != null) 'description': desc,
          'isActive': isActive,
          'year': year,
          'mode': m,
          if (amount != null) 'amount': amount,
          'academicSession': year,
        },
        userId: userId,
        version: 1,
        deviceId: deviceId,
        userDisplayName: userDisplayName,
        screen: screen,
      );
    }
  }

  /// Soft-deactivate a mission (isActive = false). Requires Admin Level 01.
  /// [userId], [userDisplayName], [screen] used for change-set if provided.
  Future<void> setMissionInactive(
    int id, {
    required UserRole userRole,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    if (!RolePermissions.canManageMissions(userRole)) {
      throw StateError('Role cannot manage missions');
    }
    final row = await getMission(id);
    if (row == null) throw StateError('Mission not found');
    await (_db.update(_db.missions)..where((t) => t.id.equals(id))).write(
      MissionsCompanion(
          isActive: const Value(false), updatedAt: Value(DateTime.now()),),
    );
    if (userId != null) {
      await _insertChangeSet(
        table: 'missions',
        recordId: id.toString(),
        operation: 'UPDATE',
        payload: {
          'isActive': false,
          if (userDisplayName != null) 'userDisplayName': userDisplayName,
          if (screen != null) 'screen': screen,
        },
        userId: userId,
        version: 1,
        deviceId: deviceId,
        userDisplayName: userDisplayName,
        screen: screen,
      );
    }
  }

  // --- Participations

  /// Stream of participations for one mission (for slot count and sign-up dialog).
  Stream<List<MissionParticipation>> watchParticipationsForMission(
      int missionId,) {
    return (_db.select(_db.missionParticipations)
          ..where((t) => t.missionId.equals(missionId)))
        .watch();
  }

  /// Stream of participations for one student (for student summary Missions tab).
  Stream<List<MissionParticipation>> watchParticipationsForStudent(
      int studentId,) {
    return (_db.select(_db.missionParticipations)
          ..where((t) => t.studentId.equals(studentId)))
        .watch();
  }

  /// Builds MissionParticipationRow list from join rows and payment sum map.
  List<MissionParticipationRow> _buildParticipationRows(
    List<JoinedRow> rows,
    Map<int, double> paymentSums,
    MissionParticipations part,
    Students students,
    Missions missions,
  ) {
    return rows.map((row) {
      final p = row.readTable(part);
      final paid = paymentSums[p.id] ?? 0.0;
      return MissionParticipationRow(
        participation: p,
        student: row.readTable(students),
        mission: row.readTable(missions),
        paidToDate: paid,
        balance: p.amount - paid,
      );
    }).toList();
  }

  /// Stream of all participation rows joined with student and mission (for Student Participation table).
  /// Includes paidToDate and balance; re-emits when participations or mission_payments change.
  Stream<List<MissionParticipationRow>> watchAllParticipationRows() {
    final part = _db.missionParticipations;
    final students = _db.students;
    final missions = _db.missions;
    final query = _db.select(part).join(
      [
        innerJoin(students, students.id.equalsExp(part.studentId)),
        innerJoin(missions, missions.id.equalsExp(part.missionId)),
      ],
    )..orderBy([
        OrderingTerm.asc(students.surname),
        OrderingTerm.asc(students.firstName),
      ]);

    List<JoinedRow> latestRows = [];
    Map<int, double> latestSums = {};
    final controller =
        StreamController<List<MissionParticipationRow>>.broadcast();

    void emit() {
      controller.add(_buildParticipationRows(
        latestRows,
        latestSums,
        part,
        students,
        missions,
      ),);
    }

    final sub1 = query.watch().listen((rows) {
      latestRows = rows;
      emit();
    });
    final paymentQuery = _db.select(_db.missionPayments);
    final sub2 = paymentQuery.watch().listen((payments) {
      latestSums = {};
      for (final p in payments) {
        latestSums[p.missionParticipationId] =
            (latestSums[p.missionParticipationId] ?? 0) + p.amount;
      }
      emit();
    });

    controller.onCancel = () {
      sub1.cancel();
      sub2.cancel();
    };
    return controller.stream;
  }

  /// Add a student to a mission. Enforces Year 2 only, optional mode match, unique (mission_id, student_id), slot limit. [amount] is required.
  Future<int> addParticipation({
    required int missionId,
    required int studentId,
    required String role,
    required double amount,
    required UserRole userRole,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    if (!RolePermissions.canManageMissions(userRole)) {
      throw StateError('Role cannot manage missions');
    }
    final mission = await getMission(missionId);
    if (mission == null) throw StateError('Mission not found');
    final student = await (_db.select(_db.students)
          ..where((s) => s.id.equals(studentId)))
        .getSingleOrNull();
    if (student == null) throw StateError('Student not found');
    final year2Class = await _classRepo.getClassByName('Year 2');
    if (year2Class == null || student.classId != year2Class.id) {
      throw StateError('Missions apply to Year 2 students only');
    }
    if (mission.mode != 'Both') {
      if (student.mode != mission.mode) {
        throw StateError('This mission is for ${mission.mode} students only');
      }
    }
    final existing = await (_db.select(_db.missionParticipations)
          ..where(
            (t) =>
                t.missionId.equals(missionId) & t.studentId.equals(studentId),
          ))
        .getSingleOrNull();
    if (existing != null) {
      throw StateError('Student is already signed up for this mission');
    }
    final count = await (_db.selectOnly(_db.missionParticipations)
          ..addColumns([_db.missionParticipations.id.count()])
          ..where(_db.missionParticipations.missionId.equals(missionId)))
        .getSingle();
    final taken = count.read(_db.missionParticipations.id.count()) ?? 0;
    if (taken >= mission.slotsTotal) {
      throw StateError('No slots available for this mission');
    }
    final resolvedRole = role.trim().isEmpty ? 'Participant' : role.trim();
    final companion = MissionParticipationsCompanion.insert(
      missionId: missionId,
      studentId: studentId,
      role: resolvedRole,
      amount: Value(amount),
    );
    final id = await _db.into(_db.missionParticipations).insert(companion);
    if (userId != null) {
      await _insertChangeSet(
        table: 'mission_participations',
        recordId: id.toString(),
        operation: 'INSERT',
        payload: {
          'missionId': missionId,
          'studentId': studentId,
          'role': resolvedRole,
          'amount': amount,
        },
        userId: userId,
        version: 1,
        deviceId: deviceId,
        userDisplayName: userDisplayName,
        screen: screen,
      );
    }
    return id;
  }

  /// Remove a participation by id.
  Future<void> removeParticipation(
    int id, {
    required UserRole userRole,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    if (!RolePermissions.canManageMissions(userRole)) {
      throw StateError('Role cannot manage missions');
    }
    final row = await (_db.select(_db.missionParticipations)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    await (_db.delete(_db.missionParticipations)..where((t) => t.id.equals(id)))
        .go();
    if (userId != null && row != null) {
      await _insertChangeSet(
        table: 'mission_participations',
        recordId: id.toString(),
        operation: 'DELETE',
        payload: {
          'missionId': row.missionId,
          'studentId': row.studentId,
          'role': row.role,
          'amount': row.amount,
        },
        userId: userId,
        version: 1,
        deviceId: deviceId,
        userDisplayName: userDisplayName,
        screen: screen,
      );
    }
  }

  /// Stream of payments for a participation (for Record payment dialog / list).
  Stream<List<MissionPayment>> watchPaymentsForParticipation(
      int participationId,) {
    return (_db.select(_db.missionPayments)
          ..where((t) => t.missionParticipationId.equals(participationId))
          ..orderBy([(t) => OrderingTerm.desc(t.paymentDate)]))
        .watch();
  }

  /// Record a payment toward a participation (date + amount).
  Future<int> addMissionPayment({
    required int participationId,
    required DateTime paymentDate,
    required double amount,
    required UserRole userRole,
    String? academicSession,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    if (!RolePermissions.canManageFinancials(userRole)) {
      throw StateError('Role cannot manage financials');
    }
    if (amount <= 0) throw ArgumentError('Amount must be positive');
    final companion = MissionPaymentsCompanion.insert(
      missionParticipationId: participationId,
      paymentDate: paymentDate,
      amount: amount,
    );
    final id = await _db.into(_db.missionPayments).insert(companion);
    if (userId != null) {
      await _insertChangeSet(
        table: 'mission_payments',
        recordId: id.toString(),
        operation: 'INSERT',
        payload: {
          'missionParticipationId': participationId,
          'paymentDate': paymentDate.toIso8601String(),
          'amount': amount,
          if (academicSession != null) 'academicSession': academicSession,
        },
        userId: userId,
        version: 1,
        deviceId: deviceId,
        userDisplayName: userDisplayName,
        screen: screen,
      );
    }
    return id;
  }

  /// Count participations for a mission (for slots available).
  Future<int> countParticipationsForMission(int missionId) async {
    final row = await (_db.selectOnly(_db.missionParticipations)
          ..addColumns([_db.missionParticipations.id.count()])
          ..where(_db.missionParticipations.missionId.equals(missionId)))
        .getSingle();
    return row.read(_db.missionParticipations.id.count()) ?? 0;
  }

  Future<void> _insertChangeSet({
    required String table,
    required String recordId,
    required String operation,
    required Map<String, dynamic> payload,
    required String userId,
    required int version,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    final effectiveDeviceId = await _effectiveChangeSetDeviceId(deviceId);
    final fullPayload = Map<String, dynamic>.from(payload);
    if (userDisplayName != null) {
      fullPayload['userDisplayName'] = userDisplayName;
    }
    if (screen != null) fullPayload['screen'] = screen;
    await _db.into(_db.changeSets).insert(
          ChangeSetsCompanion.insert(
            id: _uuid.v4(),
            table: table,
            recordId: recordId,
            operation: operation,
            payload: jsonEncode(fullPayload),
            userId: userId,
            version: version,
            deviceId: effectiveDeviceId,
          ),
        );
    _onLocalChangeSetWritten?.call();
  }
}
