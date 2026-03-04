import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/class_repository.dart';

/// Student with resolved class name for display.
class StudentWithClass {
  const StudentWithClass({required this.student, this.className, this.classId});

  final Student student;
  final String? className;
  final int? classId;
}

/// Student repository: watch, add, update (no delete; use status change).
/// Enforces role for add/edit; writes change-sets for sync.
class StudentRepository {
  StudentRepository(this._db, [ClassRepository? classRepo])
      : _classRepo = classRepo ?? ClassRepository(_db);

  final AppDatabase _db;
  final ClassRepository _classRepo;
  static const _uuid = Uuid();

  /// Returns true if any student has the given [surname]. Used for idempotent seed checks.
  Future<bool> hasStudentWithSurname(String surname) async {
    final row = await (_db.select(_db.students)
          ..where((t) => t.surname.equals(surname)))
        .getSingleOrNull();
    return row != null;
  }

  /// Stream of students ordered by surname ASC, then firstName ASC.
  /// [statusFilter] default 'Active'; pass null for all statuses.
  /// [classIds] when non-null and non-empty, restrict to students in these classes (for facilitator scope).
  /// [mode] when non-null and non-empty, restrict to students with this study mode (e.g. 'Full-time', 'Hybrid').
  Stream<List<Student>> watchStudents({
    String? statusFilter = 'Active',
    List<int>? classIds,
    String? mode,
  }) {
    var query = _db.select(_db.students);
    query = query..where((t) {
      var pred = statusFilter != null
          ? t.status.equals(statusFilter)
          : t.id.isNotNull();
      if (classIds != null && classIds.isNotEmpty) {
        pred = pred & t.classId.isIn(classIds);
      }
      if (mode != null && mode.trim().isNotEmpty) {
        pred = pred & t.mode.equals(mode.trim());
      }
      return pred;
    });
    query = query
      ..orderBy([
        (t) => OrderingTerm.asc(t.surname),
        (t) => OrderingTerm.asc(t.firstName),
      ]);
    return query.watch();
  }

  /// Stream of students with class name resolved (for display). Same order as watchStudents.
  Stream<List<StudentWithClass>> watchStudentsWithClass({
    String? statusFilter = 'Active',
    List<int>? classIds,
    String? mode,
  }) {
    return _combineStudentsWithClasses(
      watchStudents(statusFilter: statusFilter, classIds: classIds, mode: mode),
    );
  }

  Future<List<StudentWithClass>> _resolveClasses(
    List<Student> students,
    List<SchoolClass> classes,
  ) async {
    final byId = {for (final c in classes) c.id: c.name};
    return students
        .map((s) => StudentWithClass(
              student: s,
              classId: s.classId,
              className: s.classId != null ? byId[s.classId] : null,
            ),)
        .toList();
  }

  Stream<List<StudentWithClass>> _combineStudentsWithClasses(
    Stream<List<Student>> studentsStream,
  ) {
    return studentsStream.asyncMap((students) async {
      if (students.isEmpty) return <StudentWithClass>[];
      final classes = await _classRepo.getAllClasses();
      return _resolveClasses(students, classes);
    });
  }

  /// Adds a student. Requires [userRole] with canManageStudents; throws otherwise.
  /// When [currentSessionCode] is provided (e.g. from current academic session), sets students.academic_session_id.
  /// [userId], [deviceId], [userDisplayName], [screen] used for change-set if provided.
  Future<int> addStudent(
    String surname,
    String firstName, {
    required UserRole userRole,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
    int? classId,
    String? mode,
    String? admissionYear,
    String? contactInfo,
    String? email,
    bool? handbook,
    bool? mediaRelease,
    bool? accidentWaiver,
    String? currentSessionCode,
  }) async {
    if (!RolePermissions.canManageStudents(userRole)) {
      throw StateError('Role cannot add students');
    }
    final sessionId = currentSessionCode != null && currentSessionCode.trim().isNotEmpty
        ? await _getSessionIdByCode(currentSessionCode.trim())
        : null;
    final companion = StudentsCompanion.insert(
      surname: surname.trim(),
      firstName: firstName.trim(),
      classId: classId != null ? Value(classId) : const Value.absent(),
      mode: (mode != null && mode.trim().isNotEmpty)
          ? Value(mode.trim())
          : const Value.absent(),
      admissionYear: (admissionYear != null && admissionYear.trim().isNotEmpty)
          ? Value(admissionYear.trim())
          : const Value.absent(),
      contactInfo: (contactInfo != null && contactInfo.trim().isNotEmpty)
          ? Value(contactInfo.trim())
          : const Value.absent(),
      email: (email != null && email.trim().isNotEmpty)
          ? Value(email.trim())
          : const Value.absent(),
      handbook: Value(handbook ?? false),
      mediaRelease: Value(mediaRelease ?? false),
      accidentWaiver: Value(accidentWaiver ?? false),
      academicSessionId: sessionId != null ? Value(sessionId) : const Value.absent(),
    );
    final id = await _db.into(_db.students).insert(companion);
    if (userId != null) {
      final payload = <String, dynamic>{
        'surname': surname,
        'firstName': firstName,
        'studentName': '$surname, $firstName',
        if (classId != null) 'classId': classId,
        if (mode != null && mode.trim().isNotEmpty) 'mode': mode.trim(),
        if (admissionYear != null && admissionYear.trim().isNotEmpty)
          'admissionYear': admissionYear.trim(),
        if (contactInfo != null && contactInfo.trim().isNotEmpty)
          'contactInfo': contactInfo.trim(),
        if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
        'handbook': handbook ?? false,
        'mediaRelease': mediaRelease ?? false,
        'accidentWaiver': accidentWaiver ?? false,
        if (userDisplayName != null) 'userDisplayName': userDisplayName,
        if (screen != null) 'screen': screen,
      };
      await _insertChangeSet(
        table: 'students',
        recordId: id.toString(),
        operation: 'INSERT',
        payload: payload,
        userId: userId,
        version: 1,
        deviceId: deviceId ?? 'legacy',
        userDisplayName: userDisplayName,
        screen: screen,
      );
    }
    return id;
  }

  /// Updates student. For name/field edits requires canManageStudents; status change always allowed.
  /// [userId], [deviceId], [userDisplayName], [screen] used for change-set if provided; for status-only use STATUS_CHANGE.
  /// Boolean fields are only updated if explicitly provided (not null).
  Future<void> updateStudent(
    int id, {
    String? surname,
    String? firstName,
    String? status,
    int? classId,
    String? mode,
    String? admissionYear,
    String? contactInfo,
    String? email,
    bool? handbook,
    bool? mediaRelease,
    bool? accidentWaiver,
    required UserRole userRole,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    final row = await (_db.select(_db.students)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return;

    final boolHandbookChanged = handbook != null && handbook != row.handbook;
    final boolMediaReleaseChanged =
        mediaRelease != null && mediaRelease != row.mediaRelease;
    final boolAccidentWaiverChanged =
        accidentWaiver != null && accidentWaiver != row.accidentWaiver;

    final isStatusOnly = surname == null &&
        firstName == null &&
        classId == null &&
        mode == null &&
        admissionYear == null &&
        contactInfo == null &&
        email == null &&
        !boolHandbookChanged &&
        !boolMediaReleaseChanged &&
        !boolAccidentWaiverChanged &&
        status != null;

    if (!isStatusOnly && !RolePermissions.canManageStudents(userRole)) {
      throw StateError('Role cannot edit students');
    }

    final isFullUpdate = surname != null && firstName != null;
    final newVersion = row.version + 1;
    final companion = StudentsCompanion(
      id: Value(id),
      surname: surname != null ? Value(surname.trim()) : const Value.absent(),
      firstName:
          firstName != null ? Value(firstName.trim()) : const Value.absent(),
      status: status != null ? Value(status) : const Value.absent(),
      classId: isFullUpdate
          ? (classId != null ? Value(classId) : const Value(null))
          : (classId != null ? Value(classId) : const Value.absent()),
      mode: isFullUpdate
          ? (mode != null && mode.trim().isNotEmpty
              ? Value(mode.trim())
              : const Value(null))
          : (mode != null && mode.trim().isNotEmpty
              ? Value(mode.trim())
              : const Value.absent()),
      admissionYear: isFullUpdate
          ? (admissionYear != null && admissionYear.trim().isNotEmpty
              ? Value(admissionYear.trim())
              : const Value(null))
          : (admissionYear != null && admissionYear.trim().isNotEmpty
              ? Value(admissionYear.trim())
              : const Value.absent()),
      contactInfo: isFullUpdate
          ? (contactInfo != null && contactInfo.trim().isNotEmpty
              ? Value(contactInfo.trim())
              : const Value(null))
          : (contactInfo != null && contactInfo.trim().isNotEmpty
              ? Value(contactInfo.trim())
              : const Value.absent()),
      email: isFullUpdate
          ? (email != null && email.trim().isNotEmpty
              ? Value(email.trim())
              : const Value(null))
          : (email != null && email.trim().isNotEmpty
              ? Value(email.trim())
              : const Value.absent()),
      handbook: handbook != null ? Value(handbook) : const Value.absent(),
      mediaRelease:
          mediaRelease != null ? Value(mediaRelease) : const Value.absent(),
      accidentWaiver:
          accidentWaiver != null ? Value(accidentWaiver) : const Value.absent(),
      updatedAt: Value(DateTime.now()),
      version: Value(newVersion),
    );
    await (_db.update(_db.students)..where((t) => t.id.equals(id)))
        .write(companion);

    if (userId != null) {
      final operation = isStatusOnly ? 'STATUS_CHANGE' : 'UPDATE';
      final effectiveSurname = surname ?? row.surname;
      final effectiveFirstName = firstName ?? row.firstName;
      final studentName = '$effectiveSurname, $effectiveFirstName';
      final effectiveClassId = classId ?? row.classId;
      final effectiveMode = mode ?? row.mode;
      final payload = <String, dynamic>{
        if (surname != null) 'surname': surname,
        if (firstName != null) 'firstName': firstName,
        'studentName': studentName,
        if (effectiveClassId != null) 'classId': effectiveClassId,
        if (effectiveMode != null && effectiveMode.isNotEmpty) 'studentMode': effectiveMode,
        if (status != null) 'status': status,
        if (isFullUpdate || (mode != null && mode.trim().isNotEmpty))
          'mode': (mode != null && mode.trim().isNotEmpty) ? mode.trim() : null,
        if (isFullUpdate ||
            (admissionYear != null && admissionYear.trim().isNotEmpty))
          'admissionYear':
              (admissionYear != null && admissionYear.trim().isNotEmpty)
                  ? admissionYear.trim()
                  : null,
        if (isFullUpdate ||
            (contactInfo != null && contactInfo.trim().isNotEmpty))
          'contactInfo': (contactInfo != null && contactInfo.trim().isNotEmpty)
              ? contactInfo.trim()
              : null,
        if (isFullUpdate || (email != null && email.trim().isNotEmpty))
          'email':
              (email != null && email.trim().isNotEmpty) ? email.trim() : null,
        if (handbook != null) 'handbook': handbook,
        if (mediaRelease != null) 'mediaRelease': mediaRelease,
        if (accidentWaiver != null) 'accidentWaiver': accidentWaiver,
        'version': newVersion,
        if (userDisplayName != null) 'userDisplayName': userDisplayName,
        if (screen != null) 'screen': screen,
      };
      await _insertChangeSet(
        table: 'students',
        recordId: id.toString(),
        operation: operation,
        payload: payload,
        userId: userId,
        deviceId: deviceId ?? 'legacy',
        version: newVersion,
        userDisplayName: userDisplayName,
        screen: screen,
      );
    }
  }

  /// Promotes multiple students to the target class. Writes one change-set per student.
  Future<void> promoteStudents(
    List<int> studentIds,
    int targetClassId, {
    required UserRole userRole,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    if (!RolePermissions.canManageStudents(userRole)) {
      throw StateError('Role cannot promote students');
    }
    if (studentIds.isEmpty) return;
    for (final id in studentIds) {
      final row = await (_db.select(_db.students)..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (row == null) continue;
      final newVersion = row.version + 1;
      await (_db.update(_db.students)..where((t) => t.id.equals(id))).write(
        StudentsCompanion(
          classId: Value(targetClassId),
          updatedAt: Value(DateTime.now()),
          version: Value(newVersion),
        ),
      );
      if (userId != null) {
        final payload = <String, dynamic>{
          'classId': targetClassId,
          'version': newVersion,
          'studentName': '${row.surname}, ${row.firstName}',
          if (row.mode != null && row.mode!.isNotEmpty) 'studentMode': row.mode,
          if (userDisplayName != null) 'userDisplayName': userDisplayName,
          if (screen != null) 'screen': screen,
        };
        await _insertChangeSet(
          table: 'students',
          recordId: id.toString(),
          operation: 'UPDATE',
          payload: payload,
          userId: userId,
          deviceId: deviceId ?? 'legacy',
          version: newVersion,
          userDisplayName: userDisplayName,
          screen: screen,
        );
      }
    }
  }

  /// Bulk updates handbook field to true for multiple students.
  /// Only updates students where handbook is currently false.
  /// Requires [userRole] with canManageStudents; throws otherwise.
  /// [userId], [userDisplayName], [screen] used for change-set if provided.
  /// Returns the count of students updated.
  Future<int> bulkUpdateHandbook({
    required List<int> studentIds,
    required UserRole userRole,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    if (!RolePermissions.canManageStudents(userRole)) {
      throw StateError('Role cannot manage students');
    }
    if (studentIds.isEmpty) return 0;

    // Fetch all students that need updating (where handbook=false)
    final studentsToUpdate = await (_db.select(_db.students)
          ..where((t) => t.id.isIn(studentIds) & t.handbook.equals(false)))
        .get();

    if (studentsToUpdate.isEmpty) return 0;

    // Use a transaction to batch all operations
    return await _db.transaction(() async {
      int count = 0;
      final now = DateTime.now();

      for (final student in studentsToUpdate) {
        final newVersion = student.version + 1;
        final companion = StudentsCompanion(
          id: Value(student.id),
          handbook: const Value(true),
          updatedAt: Value(now),
          version: Value(newVersion),
        );
        await (_db.update(_db.students)..where((t) => t.id.equals(student.id)))
            .write(companion);

        if (userId != null) {
          final studentName = '${student.surname}, ${student.firstName}';
          final payload = <String, dynamic>{
            'handbook': true,
            'version': newVersion,
            'studentName': studentName,
            if (student.classId != null) 'classId': student.classId,
            if (student.mode != null && student.mode!.isNotEmpty) 'studentMode': student.mode,
            if (userDisplayName != null) 'userDisplayName': userDisplayName,
            if (screen != null) 'screen': screen,
          };
          await _insertChangeSet(
            table: 'students',
            recordId: student.id.toString(),
            operation: 'UPDATE',
            payload: payload,
            userId: userId,
            version: newVersion,
            deviceId: deviceId ?? 'legacy',
            userDisplayName: userDisplayName,
            screen: screen,
          );
        }
        count++;
      }

      return count;
    });
  }

  Future<int?> _getSessionIdByCode(String code) async {
    if (code.trim().isEmpty) return null;
    try {
      final result = await _db.customSelect(
        'SELECT id FROM academic_sessions WHERE code = ? LIMIT 1',
        variables: [Variable.withString(code.trim())],
        readsFrom: const {},
      ).getSingleOrNull();
      return result?.data['id'] as int?;
    } catch (_) {
      return null;
    }
  }

  Future<void> _insertChangeSet({
    required String table,
    required String recordId,
    required String operation,
    required Map<String, dynamic> payload,
    required String userId,
    required int version,
    required String deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    final fullPayload = Map<String, dynamic>.from(payload);
    if (userDisplayName != null) fullPayload['userDisplayName'] = userDisplayName;
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
            deviceId: deviceId,
          ),
        );
  }
}
