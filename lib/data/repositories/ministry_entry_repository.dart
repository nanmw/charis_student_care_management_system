import 'dart:async';

import 'package:drift/drift.dart';

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
  });

  final String? search;
  final String? year;
  final String? ministryType;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  /// When non-null and non-empty, only entries whose ministry_entries.class_id is in this list.
  final List<int>? classIds;

  MinistryEntryFilters copyWith({
    String? search,
    String? year,
    String? ministryType,
    DateTime? dateFrom,
    DateTime? dateTo,
    List<int>? classIds,
  }) {
    return MinistryEntryFilters(
      search: search ?? this.search,
      year: year ?? this.year,
      ministryType: ministryType ?? this.ministryType,
      dateFrom: dateFrom ?? this.dateFrom,
      dateTo: dateTo ?? this.dateTo,
      classIds: classIds ?? this.classIds,
    );
  }
}

/// Repository for ministry hours entries: paginated list, summary stats, CRUD.
class MinistryEntryRepository {
  MinistryEntryRepository(this._db);

  final AppDatabase _db;

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
    if (filters.ministryType != null && filters.ministryType!.trim().isNotEmpty) {
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
    if (filters.classIds != null && filters.classIds!.isNotEmpty) {
      final placeholders = List.filled(filters.classIds!.length, '?').join(',');
      conditions.add('m.class_id IN ($placeholders)');
      for (final id in filters.classIds!) {
        variables.add(Variable.withInt(id));
      }
    }

    final whereSql =
        conditions.isEmpty ? '1=1' : conditions.join(' AND ');
    return (whereSql, variables);
  }

  /// Paginated list of ministry entries with student names.
  Future<List<MinistryEntryWithStudent>> getMinistryEntriesPage(
    int limit,
    int offset, {
    MinistryEntryFilters filters = const MinistryEntryFilters(),
  }) async {
    final (whereSql, whereVars) = _buildWhereAndVars(filters);
    final allVars = [...whereVars, Variable.withInt(limit), Variable.withInt(offset)];

    final query = _db.customSelect(
      '''
      SELECT m.id, m.student_id, m.year, m.term, m.class_id, m.study_mode,
             m.ministry_type, m.date, m.hours,
             m.supervisor, m.approved, m.notes, m.created_at, m.updated_at,
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
    final controller = StreamController<List<MinistryHoursSummaryRow>>.broadcast();
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
    final (whereSql, whereVars) = _buildWhereAndVars(filters);

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

  /// Summary stats for dashboard cards. When [classIds] is non-null and non-empty, only entries in those classes.
  Future<MinistrySummaryStats> getMinistrySummaryStats({
    List<int>? classIds,
  }) async {
    final String whereClause;
    final List<Variable> whereVars;
    if (classIds != null && classIds.isNotEmpty) {
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
  Stream<MinistrySummaryStats> watchMinistrySummaryStats({List<int>? classIds}) {
    return _db.select(_db.ministryEntries).watch().asyncMap((_) async {
      return getMinistrySummaryStats(classIds: classIds);
    });
  }

  /// Total ministry hours per student (all entries, sum of hours). Used for dashboard.
  Future<Map<int, double>> getTotalHoursByStudent() async {
    final query = _db.selectOnly(_db.ministryEntries)
      ..addColumns([_db.ministryEntries.studentId, _db.ministryEntries.hours.sum()])
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
  Future<int> insert(MinistryEntriesCompanion companion) async {
    return await _db.into(_db.ministryEntries).insert(companion);
  }

  /// Update an existing ministry entry by id.
  Future<void> update(int id, MinistryEntriesCompanion companion) async {
    await (_db.update(_db.ministryEntries)..where((t) => t.id.equals(id)))
        .write(companion);
  }

  /// Delete a ministry entry by id.
  Future<void> delete(int id) async {
    await (_db.delete(_db.ministryEntries)..where((t) => t.id.equals(id)))
        .go();
  }
}
