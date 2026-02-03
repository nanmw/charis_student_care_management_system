import 'package:drift/drift.dart';

import 'package:charis_student_care/data/database/app_database.dart';

/// Change sets repository: watch recent changes for activity feed.
class ChangeSetsRepository {
  ChangeSetsRepository(this._db);

  final AppDatabase _db;

  /// Stream of recent change sets, ordered by timestamp descending.
  /// Returns the [limit] most recent changes.
  Stream<List<ChangeSet>> watchRecentChanges({int limit = 10}) {
    return (_db.select(_db.changeSets)
          ..orderBy([(t) => OrderingTerm.desc(t.timestamp)])
          ..limit(limit))
        .watch();
  }
}
