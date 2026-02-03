import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/data/database/app_database.dart';

/// Student repository: watch, add, update (no delete; use status change).
/// Enforces role for add/edit; writes change-sets for sync.
class StudentRepository {
  StudentRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  /// Returns true if any student has the given [surname]. Used for idempotent seed checks.
  Future<bool> hasStudentWithSurname(String surname) async {
    final row = await (_db.select(_db.students)..where((t) => t.surname.equals(surname))).getSingleOrNull();
    return row != null;
  }

  /// Stream of students ordered by surname ASC, then firstName ASC.
  /// [statusFilter] default 'Active'; pass null for all statuses.
  Stream<List<Student>> watchStudents({String? statusFilter = 'Active'}) {
    var query = _db.select(_db.students);
    if (statusFilter != null) {
      query = query..where((t) => t.status.equals(statusFilter));
    }
    query = query
      ..orderBy([
        (t) => OrderingTerm.asc(t.surname),
        (t) => OrderingTerm.asc(t.firstName),
      ]);
    return query.watch();
  }

  /// Adds a student. Requires [userRole] with canManageStudents; throws otherwise.
  /// [userId] used for change-set if provided.
  Future<int> addStudent(
    String surname,
    String firstName, {
    required UserRole userRole,
    String? userId,
    String? year,
    String? mode,
    String? admissionYear,
    String? contactInfo,
    String? email,
    bool? handbook,
    bool? mediaRelease,
    bool? accidentWaiver,
  }) async {
    if (!RolePermissions.canManageStudents(userRole)) {
      throw StateError('Role cannot add students');
    }
    final companion = StudentsCompanion.insert(
      surname: surname.trim(),
      firstName: firstName.trim(),
      year: (year != null && year.trim().isNotEmpty) ? Value(year.trim()) : const Value.absent(),
      mode: (mode != null && mode.trim().isNotEmpty) ? Value(mode.trim()) : const Value.absent(),
      admissionYear: (admissionYear != null && admissionYear.trim().isNotEmpty) ? Value(admissionYear.trim()) : const Value.absent(),
      contactInfo: (contactInfo != null && contactInfo.trim().isNotEmpty) ? Value(contactInfo.trim()) : const Value.absent(),
      email: (email != null && email.trim().isNotEmpty) ? Value(email.trim()) : const Value.absent(),
      // Always explicitly set boolean values, even when false
      // Form passes non-nullable bool, but we accept bool? for flexibility
      // Always set explicitly to ensure values are written to database
      handbook: Value(handbook ?? false),
      mediaRelease: Value(mediaRelease ?? false),
      accidentWaiver: Value(accidentWaiver ?? false),
    );
    final id = await _db.into(_db.students).insert(companion);
    if (userId != null) {
      final payload = <String, dynamic>{
        'surname': surname,
        'firstName': firstName,
        if (year != null && year.trim().isNotEmpty) 'year': year.trim(),
        if (mode != null && mode.trim().isNotEmpty) 'mode': mode.trim(),
        if (admissionYear != null && admissionYear.trim().isNotEmpty) 'admissionYear': admissionYear.trim(),
        if (contactInfo != null && contactInfo.trim().isNotEmpty) 'contactInfo': contactInfo.trim(),
        if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
        // Always include boolean values in change-set payload
        'handbook': handbook ?? false,
        'mediaRelease': mediaRelease ?? false,
        'accidentWaiver': accidentWaiver ?? false,
      };
      await _insertChangeSet(
        table: 'students',
        recordId: id.toString(),
        operation: 'INSERT',
        payload: payload,
        userId: userId,
        version: 1,
      );
    }
    return id;
  }

  /// Updates student. For name/field edits requires canManageStudents; status change always allowed.
  /// [userId] used for change-set if provided; for status-only use STATUS_CHANGE.
  /// Boolean fields are only updated if explicitly provided (not null).
  Future<void> updateStudent(
    int id, {
    String? surname,
    String? firstName,
    String? status,
    String? year,
    String? mode,
    String? admissionYear,
    String? contactInfo,
    String? email,
    bool? handbook,
    bool? mediaRelease,
    bool? accidentWaiver,
    required UserRole userRole,
    String? userId,
  }) async {
    final row = await (_db.select(_db.students)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return;

    // Check if this is a status-only change (excluding boolean fields since form always passes them)
    // Compare boolean values with current values to determine if they actually changed
    final boolHandbookChanged = handbook != null && handbook != row.handbook;
    final boolMediaReleaseChanged = mediaRelease != null && mediaRelease != row.mediaRelease;
    final boolAccidentWaiverChanged = accidentWaiver != null && accidentWaiver != row.accidentWaiver;
    
    final isStatusOnly = surname == null && 
        firstName == null && 
        year == null && 
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

    // Determine if this is a full form update (surname and firstName provided) vs partial update
    // In full form updates, null optional fields mean "clear this field"
    // In partial updates, null means "don't update this field"
    final isFullUpdate = surname != null && firstName != null;

    final newVersion = row.version + 1;
    final companion = StudentsCompanion(
      id: Value(id),
      surname: surname != null ? Value(surname.trim()) : const Value.absent(),
      firstName: firstName != null ? Value(firstName.trim()) : const Value.absent(),
      status: status != null ? Value(status) : const Value.absent(),
      // For optional string fields: if full update and null/empty, set to null; otherwise only update if provided
      year: isFullUpdate
          ? (year != null && year.trim().isNotEmpty ? Value(year.trim()) : const Value(null))
          : (year != null && year.trim().isNotEmpty ? Value(year.trim()) : const Value.absent()),
      mode: isFullUpdate
          ? (mode != null && mode.trim().isNotEmpty ? Value(mode.trim()) : const Value(null))
          : (mode != null && mode.trim().isNotEmpty ? Value(mode.trim()) : const Value.absent()),
      admissionYear: isFullUpdate
          ? (admissionYear != null && admissionYear.trim().isNotEmpty ? Value(admissionYear.trim()) : const Value(null))
          : (admissionYear != null && admissionYear.trim().isNotEmpty ? Value(admissionYear.trim()) : const Value.absent()),
      contactInfo: isFullUpdate
          ? (contactInfo != null && contactInfo.trim().isNotEmpty ? Value(contactInfo.trim()) : const Value(null))
          : (contactInfo != null && contactInfo.trim().isNotEmpty ? Value(contactInfo.trim()) : const Value.absent()),
      email: isFullUpdate
          ? (email != null && email.trim().isNotEmpty ? Value(email.trim()) : const Value(null))
          : (email != null && email.trim().isNotEmpty ? Value(email.trim()) : const Value.absent()),
      // Only update boolean fields if explicitly provided (not null)
      handbook: handbook != null ? Value(handbook) : const Value.absent(),
      mediaRelease: mediaRelease != null ? Value(mediaRelease) : const Value.absent(),
      accidentWaiver: accidentWaiver != null ? Value(accidentWaiver) : const Value.absent(),
      updatedAt: Value(DateTime.now()),
      version: Value(newVersion),
    );
    await (_db.update(_db.students)..where((t) => t.id.equals(id))).write(companion);

    if (userId != null) {
      final operation = isStatusOnly ? 'STATUS_CHANGE' : 'UPDATE';
      final payload = <String, dynamic>{
        if (surname != null) 'surname': surname,
        if (firstName != null) 'firstName': firstName,
        if (status != null) 'status': status,
        // Include optional fields in payload if they're being updated (either set to a value or cleared in full update)
        if (isFullUpdate || (year != null && year.trim().isNotEmpty)) 
          'year': (year != null && year.trim().isNotEmpty) ? year.trim() : null,
        if (isFullUpdate || (mode != null && mode.trim().isNotEmpty)) 
          'mode': (mode != null && mode.trim().isNotEmpty) ? mode.trim() : null,
        if (isFullUpdate || (admissionYear != null && admissionYear.trim().isNotEmpty)) 
          'admissionYear': (admissionYear != null && admissionYear.trim().isNotEmpty) ? admissionYear.trim() : null,
        if (isFullUpdate || (contactInfo != null && contactInfo.trim().isNotEmpty)) 
          'contactInfo': (contactInfo != null && contactInfo.trim().isNotEmpty) ? contactInfo.trim() : null,
        if (isFullUpdate || (email != null && email.trim().isNotEmpty)) 
          'email': (email != null && email.trim().isNotEmpty) ? email.trim() : null,
        // Only include boolean values in change-set if they were explicitly provided
        if (handbook != null) 'handbook': handbook,
        if (mediaRelease != null) 'mediaRelease': mediaRelease,
        if (accidentWaiver != null) 'accidentWaiver': accidentWaiver,
        'version': newVersion,
      };
      await _insertChangeSet(
        table: 'students',
        recordId: id.toString(),
        operation: operation,
        payload: payload,
        userId: userId,
        version: newVersion,
      );
    }
  }

  Future<void> _insertChangeSet({
    required String table,
    required String recordId,
    required String operation,
    required Map<String, dynamic> payload,
    required String userId,
    required int version,
  }) async {
    await _db.into(_db.changeSets).insert(
          ChangeSetsCompanion.insert(
            id: _uuid.v4(),
            table: table,
            recordId: recordId,
            operation: operation,
            payload: jsonEncode(payload),
            userId: userId,
            version: version,
          ),
        );
  }
}
