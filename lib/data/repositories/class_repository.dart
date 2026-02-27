import 'package:drift/drift.dart';

import 'package:charis_student_care/data/database/app_database.dart';

/// Repository for classes (academic year levels: Year 1, Year 2, Year 3).
class ClassRepository {
  ClassRepository(this._db);

  final AppDatabase _db;

  /// Stream of all classes ordered by sortOrder then name.
  Stream<List<SchoolClass>> watchClasses() {
    return (_db.select(_db.classes)
          ..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.name),
          ]))
        .watch();
  }

  /// One-time fetch of all classes ordered by sortOrder then name.
  Future<List<SchoolClass>> getAllClasses() async {
    return (_db.select(_db.classes)
          ..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.name),
          ]))
        .get();
  }

  /// Fetch a class by id, or null if not found.
  Future<SchoolClass?> getClassById(int id) async {
    return (_db.select(_db.classes)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// Fetch a class by name (e.g. "Year 2"), or null if not found.
  Future<SchoolClass?> getClassByName(String name) async {
    return (_db.select(_db.classes)..where((t) => t.name.equals(name)))
        .getSingleOrNull();
  }

  /// Insert a new class. Returns the new row id.
  Future<int> insert(ClassesCompanion companion) async {
    return await _db.into(_db.classes).insert(companion);
  }

  /// Update an existing class by id.
  Future<void> update(int id, ClassesCompanion companion) async {
    await (_db.update(_db.classes)..where((t) => t.id.equals(id)))
        .write(companion);
  }

  /// Set or clear the facilitator for a class.
  Future<void> updateFacilitator(int classId, int? userId) async {
    await (_db.update(_db.classes)..where((t) => t.id.equals(classId))).write(
      ClassesCompanion(
        facilitatorUserId: Value(userId),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Classes assigned to the given facilitator (where facilitatorUserId == userId).
  Future<List<SchoolClass>> getClassesByFacilitatorUserId(int userId) async {
    return (_db.select(_db.classes)
          ..where((t) => t.facilitatorUserId.equals(userId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.name),
          ]))
        .get();
  }

  /// Class ids assigned to the given facilitator (for scope filtering).
  Future<List<int>> getClassIdsByFacilitatorUserId(int userId) async {
    final classes = await getClassesByFacilitatorUserId(userId);
    return classes.map((c) => c.id).toList();
  }
}
