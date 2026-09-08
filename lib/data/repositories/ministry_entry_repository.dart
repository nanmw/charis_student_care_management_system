import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:charis_student_care/core/config/sync_folder_config.dart';
import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/data/database/app_database.dart';

/// DTO for a ministry entry with student display name (Surname, FirstName).
class MinistryEntryWithStudent {
  const MinistryEntryWithStudent({
    required this.entry,
    required this.studentSurname,
    required this.studentFirstName,
  });

  final MinistryEntry entry;
  final String studentSurname;
  final String studentFirstName;

  String get studentDisplayName => '$studentSurname, $studentFirstName';
}

/// One row in the ministry hours summary table: one student with Term 1/2/3 and Total.
class MinistryHoursSummaryRow {
  const MinistryHoursSummaryRow({
    required this.studentId,
    required this.firstName,
    required this.lastName,
    required this.term1Hours,
    required this.term2Hours,
    required this.term3Hours,
  });

  final int studentId;
  final String firstName;
  final String lastName;
  final double term1Hours;
  final double term2Hours;
  final double term3Hours;

  double get totalHours => term1Hours + term2Hours + term3Hours;
}

/// Summary stats for the ministry hours dashboard cards.
class MinistrySummaryStats {
  const MinistrySummaryStats({
    required this.totalHours,
    required this.avgHoursPerStudent,
    required this.pendingApprovalsCount,
    required this.approvedHours,
  });

  final double totalHours;
  final double avgHoursPerStudent;
  final int pendingApprovalsCount;
  final double approvedHours;
}

/// Filter parameters for ministry entries list.
class MinistryEntryFilters {
  const MinistryEntryFilters({
    this.search,
    this.year,
    this.ministryType,
    this.dateFrom,
    this.dateTo,
    this.classIds,
    this.academicSession,
  });

  final String? search;
  final String? year;
  final String? ministryType;
  final DateTime? dateFrom;
  final DateTime? dateTo;

  /// When non-null and non-empty, only entries whose ministry_entries.class_id is in this list.
  final List<int>? classIds;

  /// When non-null and non-empty, filter by academic session (resolves to academic_session_id).
  final String? academicSession;

  MinistryEntryFilters copyWith({
    String? search,
    String? year,
    String? ministryType,
    DateTime? dateFrom,
    DateTime? dateTo,
    List<int>? classIds,
    String? academicSession,
  }) {
    return MinistryEntryFilters(
      search: search ?? this.search,
      year: year ?? this.year,
      ministryType: ministryType ?? this.ministryType,
      dateFrom: dateFrom ?? this.dateFrom,
      dateTo: dateTo ?? this.dateTo,
      classIds: classIds ?? this.classIds,
      academicSession: academicSession ?? this.academicSession,
    );
  }
}

/// Repository for ministry hours entries: paginated list, summary stats, CRUD.
class MinistryEntryRepository {
  MinistryEntryRepository(
    this._db, {
    void Function()? onLocalChangeSetWritten,
  }) : _onLocalChangeSetWritten = onLocalChangeSetWritten;

  final AppDatabase _db;
  final void Function()? _onLocalChangeSetWritten;
  static const _uuid = Uuid();

  Future<String> _effectiveChangeSetDeviceId(String? deviceId) async {
    final d = deviceId?.trim();
    if (d != null && d.isNotEmpty && d != 'legacy') return d;
    return SyncFolderConfig.getOrCreateDeviceId();
  }

  Future<String?> _sessionCodeById(int? sessionId) async {
    if (sessionId == null) return null;
    try {
      final result = await _db.customSelect(
        'SELECT code FROM academic_sessions WHERE id = ? LIMIT 1',
        variables: [Variable.withInt(sessionId)],
        readsFrom: const {},
      ).getSingleOrNull();
      return result?.data['code'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Builds WHERE clause (excluding join) and variables for filters.
  (String, List<Variable>) _buildWhereAndVars(MinistryEntryFilters filters) {
    final conditions = <String>[];
    final variables = <Variable>[];

    if (filters.search != null && filters.search!.trim().isNotEmpty) {
      final term = '%${filters.search!.trim()}%';
      conditions.add('(s.surname LIKE ? OR s.first_name LIKE ?)');
      variables.add(Variable.withString(term));
      variables.add(Variable.withString(term));
    }
    if (filters.year != null && filters.year!.trim().isNotEmpty) {
      conditions.add('m.year = ?');
      variables.add(Variable.withString(filters.year!.trim()));
    }
    if (filters.ministryType != null &&
        filters.ministryType!.trim().isNotEmpty) {
      conditions.add('m.ministry_type = ?');
      variables.add(Variable.withString(filters.ministryType!.trim()));
    }
    if (filters.dateFrom != null) {
      conditions.add('m.date >= ?');
      variables.add(Variable.withDateTime(filters.dateFrom!));
    }
    if (filters.dateTo != null) {
      conditions.add('m.date <= ?');
      variables.add(Variable.withDateTime(filters.dateTo!));
    }
    if (filters.classIds != null) {
      if (filters.classIds!.isEmpty) {
        conditions.add('1 = 0');
      } else {
        final placeholders =
            List.filled(filters.classIds!.length, '?').join(',');
        conditions.add('m.class_id IN ($placeholders)');
        for (final id in filters.classIds!) {
          variables.add(Variable.withInt(id));
        }
      }
    }

    final whereSql = conditions.isEmpty ? '1=1' : conditions.join(' AND ');
    return (whereSql, variables);
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

  /// Async version that resolves [MinistryEntryFilters.academicSession] to session ID.
  Future<(String, List<Variable>)> _buildWhereAndVarsAsync(
      MinistryEntryFilters filters) async {
    var (whereSql, variables) = _buildWhereAndVars(filters);
    if (filters.academicSession != null &&
        filters.academicSession!.trim().isNotEmpty) {
      final sessionId =
          await _getSessionIdByCode(filters.academicSession!.trim());
      if (sessionId != null) {
        final conditions = whereSql == '1=1' ? <String>[] : [whereSql];
        conditions.add('m.academic_session_id = ?');
        variables = [...variables, Variable.withInt(sessionId)];
        whereSql = conditions.join(' AND ');
      }
    }
    return (whereSql, variables);
  }

  /// Paginated list of ministry entries with student names.
  Future<List<MinistryEntryWithStudent>> getMinistryEntriesPage(
    int limit,
    int offset, {
    MinistryEntryFilters filters = const MinistryEntryFilters(),
  }) async {
    final (whereSql, whereVars) = await _buildWhereAndVarsAsync(filters);
    final allVars = [
      ...whereVars,
      Variable.withInt(limit),
      Variable.withInt(offset)
    ];

    final query = _db.customSelect(
      '''
      SELECT m.id, m.student_id, m.year, m.term, m.class_id, m.study_mode,
             m.ministry_type, m.date, m.hours,
             m.supervisor, m.approved, m.notes, m.created_at, m.updated_at,
             m.academic_session_id,
             s.surname AS student_surname, s.first_name AS student_first_name
      FROM ministry_entries m
      INNER JOIN students s ON m.student_id = s.id
      WHERE $whereSql
      ORDER BY m.date DESC, m.id DESC
      LIMIT ? OFFSET ?
      ''',
      variables: allVars,
      readsFrom: {_db.ministryEntries, _db.students},
    );

    final rows = await query.get();
    return rows.map((row) {
      final entry = MinistryEntry(
        id: row.read<int>('id'),
        studentId: row.read<int>('student_id'),
        year: row.read<String>('year'),
        term: row.read<int>('term'),
        classId: row.read<int?>('class_id'),
        studyMode: row.read<String?>('study_mode'),
        ministryType: row.read<String>('ministry_type'),
        date: row.read<DateTime>('date'),
        hours: row.read<double>('hours'),
        supervisor: row.read<String?>('supervisor'),
        approved: row.read<int>('approved') == 1,
        notes: row.read<String?>('notes'),
        createdAt: row.read<DateTime>('created_at'),
        updatedAt: row.read<DateTime?>('updated_at'),
        academicSessionId: row.read<int?>('academic_session_id'),
      );
      return MinistryEntryWithStudent(
        entry: entry,
        studentSurname: row.read<String>('student_surname'),
        studentFirstName: row.read<String>('student_first_name'),
      );
    }).toList();
  }

  /// Summary of ministry hours per student for a given class and study mode.
  /// Returns one row per student (in that class/mode) with Term 1/2/3 and Total.
  /// Uses entries where class_id and study_mode match; students with no entries still appear with zero hours.
  Future<List<MinistryHoursSummaryRow>> getMinistryHoursSummary(
    int classId,
    String studyMode,
  ) async {
    final query = _db.customSelect(
      '''
      SELECT s.id AS student_id, s.first_name AS first_name, s.surname AS last_name,
             COALESCE(SUM(CASE WHEN m.term = 1 THEN m.hours ELSE 0 END), 0) AS term1_hours,
             COALESCE(SUM(CASE WHEN m.term = 2 THEN m.hours ELSE 0 END), 0) AS term2_hours,
             COALESCE(SUM(CASE WHEN m.term = 3 THEN m.hours ELSE 0 END), 0) AS term3_hours
      FROM students s
      LEFT JOIN ministry_entries m ON m.student_id = s.id AND m.class_id = ? AND m.study_mode = ?
      WHERE s.class_id = ? AND s.mode = ? AND s.status = 'Active'
      GROUP BY s.id, s.first_name, s.surname
      ORDER BY s.surname, s.first_name
      ''',
      variables: [
        Variable.withInt(classId),
        Variable.withString(studyMode),
        Variable.withInt(classId),
        Variable.withString(studyMode),
      ],
      readsFrom: {_db.students, _db.ministryEntries},
    );
    final rows = await query.get();
    return rows.map((row) {
      return MinistryHoursSummaryRow(
        studentId: row.read<int>('student_id'),
        firstName: row.read<String>('first_name'),
        lastName: row.read<String>('last_name'),
        term1Hours: row.read<double>('term1_hours'),
        term2Hours: row.read<double>('term2_hours'),
        term3Hours: row.read<double>('term3_hours'),
      );
    }).toList();
  }

  /// Stream of ministry hours summary for the given class and mode (updates when students or entries change).
  Stream<List<MinistryHoursSummaryRow>> watchMinistryHoursSummary(
    int classId,
    String studyMode,
  ) {
    final controller =
        StreamController<List<MinistryHoursSummaryRow>>.broadcast();
    void onEvent(_) async {
      controller.add(await getMinistryHoursSummary(classId, studyMode));
    }

    final sub1 = _db.select(_db.students).watch().listen(onEvent);
    final sub2 = _db.select(_db.ministryEntries).watch().listen(onEvent);
    controller.onCancel = () {
      sub1.cancel();
      sub2.cancel();
    };
    getMinistryHoursSummary(classId, studyMode).then(controller.add);
    return controller.stream;
  }

  /// Total count of ministry entries matching filters.
  Future<int> getMinistryEntriesTotalCount({
    MinistryEntryFilters filters = const MinistryEntryFilters(),
  }) async {
    final (whereSql, whereVars) = await _buildWhereAndVarsAsync(filters);

    final countQuery = _db.customSelect(
      '''
      SELECT COUNT(*) AS c FROM ministry_entries m
      INNER JOIN students s ON m.student_id = s.id
      WHERE $whereSql
      ''',
      variables: whereVars,
      readsFrom: {_db.ministryEntries, _db.students},
    );

    final row = await countQuery.getSingle();
    return row.read<int>('c');
  }

  /// Summary stats for dashboard cards.
  /// When [classIds] is null: unscoped (admin).
  /// When [classIds] is empty: deny-all (facilitator with no classes).
  /// When non-empty: filter to those classes.
  Future<MinistrySummaryStats> getMinistrySummaryStats({
    List<int>? classIds,
  }) async {
    final String whereClause;
    final List<Variable> whereVars;
    if (classIds != null && classIds.isEmpty) {
      whereClause = '1 = 0';
      whereVars = [];
    } else if (classIds != null && classIds.isNotEmpty) {
      final placeholders = List.filled(classIds.length, '?').join(',');
      whereClause = 'class_id IN ($placeholders)';
      whereVars = classIds.map((id) => Variable.withInt(id)).toList();
    } else {
      whereClause = '1=1';
      whereVars = [];
    }

    final totalResult = await _db.customSelect(
      'SELECT COALESCE(SUM(hours), 0) AS total FROM ministry_entries WHERE $whereClause',
      variables: whereVars,
      readsFrom: {_db.ministryEntries},
    ).getSingle();
    final totalHours = totalResult.read<double>('total');

    final pendingResult = await _db.customSelect(
      'SELECT COUNT(*) AS c FROM ministry_entries WHERE $whereClause AND approved = 0',
      variables: whereVars,
      readsFrom: {_db.ministryEntries},
    ).getSingle();
    final pendingApprovalsCount = pendingResult.read<int>('c');

    final approvedResult = await _db.customSelect(
      'SELECT COALESCE(SUM(hours), 0) AS total FROM ministry_entries WHERE $whereClause AND approved = 1',
      variables: whereVars,
      readsFrom: {_db.ministryEntries},
    ).getSingle();
    final approvedHours = approvedResult.read<double>('total');

    final distinctResult = await _db.customSelect(
      'SELECT COUNT(DISTINCT student_id) AS c FROM ministry_entries WHERE $whereClause',
      variables: whereVars,
      readsFrom: {_db.ministryEntries},
    ).getSingle();
    final studentCount = distinctResult.read<int>('c');
    final avgHoursPerStudent =
        studentCount > 0 ? totalHours / studentCount : 0.0;

    return MinistrySummaryStats(
      totalHours: totalHours,
      avgHoursPerStudent: avgHoursPerStudent,
      pendingApprovalsCount: pendingApprovalsCount,
      approvedHours: approvedHours,
    );
  }

  /// Stream of summary stats (reactive when ministry_entries change). When [classIds] is non-null and non-empty, scoped to those classes.
  Stream<MinistrySummaryStats> watchMinistrySummaryStats(
      {List<int>? classIds}) {
    return _db.select(_db.ministryEntries).watch().asyncMap((_) async {
      return getMinistrySummaryStats(classIds: classIds);
    });
  }

  /// Total ministry hours per student (all entries, sum of hours). Used for dashboard.
  Future<Map<int, double>> getTotalHoursByStudent() async {
    final query = _db.selectOnly(_db.ministryEntries)
      ..addColumns(
          [_db.ministryEntries.studentId, _db.ministryEntries.hours.sum()])
      ..groupBy([_db.ministryEntries.studentId]);
    final rows = await query.get();
    final map = <int, double>{};
    for (final r in rows) {
      final id = r.read(_db.ministryEntries.studentId);
      if (id != null) {
        map[id] = r.read(_db.ministryEntries.hours.sum()) ?? 0.0;
      }
    }
    return map;
  }

  /// Stream of total ministry hours per student (reactive when ministry_entries change).
  Stream<Map<int, double>> watchTotalHoursByStudent() {
    return _db.select(_db.ministryEntries).watch().asyncMap((_) async {
      return getTotalHoursByStudent();
    });
  }

  /// Stream of ministry entries for a single student (for student summary modal).
  /// Ordered by date descending.
  Stream<List<MinistryEntry>> watchMinistryEntriesForStudent(int studentId) {
    final query = _db.select(_db.ministryEntries)
      ..where((m) => m.studentId.equals(studentId))
      ..orderBy([(m) => OrderingTerm.desc(m.date)]);
    return query.watch();
  }

  /// Insert a new ministry entry. Returns the new row id.
  /// When [userId] is provided, writes a change-set for sync.
  Future<int> insert(
    MinistryEntriesCompanion companion, {
    required UserRole userRole,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    if (!RolePermissions.canEnterMinistryHours(userRole)) {
      throw StateError('Role cannot enter ministry hours');
    }
    final id = await _insertRowAndChangeSet(
      companion,
      userId: userId,
      deviceId: deviceId,
      userDisplayName: userDisplayName,
      screen: screen,
    );
    if (userId != null) {
      _onLocalChangeSetWritten?.call();
    }
    return id;
  }

  /// Inserts many ministry entries in one transaction.
  /// Writes one INSERT change-set per row; notifies [onLocalChangeSetWritten] once.
  /// Returns the number of rows inserted. Empty [companions] is a no-op.
  Future<int> insertAll(
    List<MinistryEntriesCompanion> companions, {
    required UserRole userRole,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    if (!RolePermissions.canEnterMinistryHours(userRole)) {
      throw StateError('Role cannot enter ministry hours');
    }
    if (companions.isEmpty) return 0;

    final count = await _db.transaction(() async {
      var n = 0;
      for (final companion in companions) {
        await _insertRowAndChangeSet(
          companion,
          userId: userId,
          deviceId: deviceId,
          userDisplayName: userDisplayName,
          screen: screen,
        );
        n++;
      }
      return n;
    });
    if (userId != null && count > 0) {
      _onLocalChangeSetWritten?.call();
    }
    return count;
  }

  /// Student ids in [studentIds] that already have a ministry entry of
  /// [ministryType] on the same calendar day as [date].
  Future<List<int>> findStudentsWithEntryOnDate({
    required List<int> studentIds,
    required DateTime date,
    required String ministryType,
  }) async {
    if (studentIds.isEmpty) return [];
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final rows = await (_db.select(_db.ministryEntries)
          ..where(
            (t) =>
                t.studentId.isIn(studentIds) &
                t.ministryType.equals(ministryType) &
                t.date.isBiggerOrEqualValue(dayStart) &
                t.date.isSmallerThanValue(dayEnd),
          ))
        .get();
    final ids = rows.map((r) => r.studentId).toSet().toList()..sort();
    return ids;
  }

  /// Writes the row and optional change-set without notifying sync.
  Future<int> _insertRowAndChangeSet(
    MinistryEntriesCompanion companion, {
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    final id = await _db.into(_db.ministryEntries).insert(companion);
    if (userId != null) {
      final row = await (_db.select(_db.ministryEntries)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (row != null) {
        await _insertChangeSet(
          table: 'ministry_entries',
          recordId: id.toString(),
          operation: 'INSERT',
          payload: await _payloadFromEntry(row),
          userId: userId,
          version: 1,
          deviceId: deviceId,
          userDisplayName: userDisplayName,
          screen: screen,
          notifySync: false,
        );
      }
    }
    return id;
  }

  /// Update an existing ministry entry by id.
  Future<void> update(
    int id,
    MinistryEntriesCompanion companion, {
    required UserRole userRole,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    if (!RolePermissions.canEnterMinistryHours(userRole)) {
      throw StateError('Role cannot enter ministry hours');
    }
    await (_db.update(_db.ministryEntries)..where((t) => t.id.equals(id)))
        .write(companion);
    if (userId != null) {
      final row = await (_db.select(_db.ministryEntries)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (row != null) {
        await _insertChangeSet(
          table: 'ministry_entries',
          recordId: id.toString(),
          operation: 'UPDATE',
          payload: await _payloadFromEntry(row),
          userId: userId,
          version: 1,
          deviceId: deviceId,
          userDisplayName: userDisplayName,
          screen: screen,
        );
      }
    }
  }

  /// Delete a ministry entry by id.
  Future<void> delete(
    int id, {
    required UserRole userRole,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    if (!RolePermissions.canEnterMinistryHours(userRole)) {
      throw StateError('Role cannot enter ministry hours');
    }
    final row = await (_db.select(_db.ministryEntries)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    await (_db.delete(_db.ministryEntries)..where((t) => t.id.equals(id))).go();
    if (userId != null && row != null) {
      await _insertChangeSet(
        table: 'ministry_entries',
        recordId: id.toString(),
        operation: 'DELETE',
        payload: await _payloadFromEntry(row),
        userId: userId,
        version: 1,
        deviceId: deviceId,
        userDisplayName: userDisplayName,
        screen: screen,
      );
    }
  }

  Future<Map<String, dynamic>> _payloadFromEntry(MinistryEntry row) async {
    final sessionCode = await _sessionCodeById(row.academicSessionId);
    String? className;
    if (row.classId != null) {
      final c = await (_db.select(_db.classes)
            ..where((t) => t.id.equals(row.classId!)))
          .getSingleOrNull();
      className = c?.name;
    }
    return {
      'studentId': row.studentId,
      'year': row.year,
      'term': row.term,
      if (className != null && className.isNotEmpty) 'className': className,
      if (row.studyMode != null) 'studyMode': row.studyMode,
      'ministryType': row.ministryType,
      'date': row.date.toIso8601String(),
      'hours': row.hours,
      if (row.supervisor != null) 'supervisor': row.supervisor,
      'approved': row.approved,
      if (row.notes != null) 'notes': row.notes,
      if (sessionCode != null) 'academicSession': sessionCode,
    };
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
    bool notifySync = true,
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
    if (notifySync) {
      _onLocalChangeSetWritten?.call();
    }
  }
}
