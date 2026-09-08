import 'dart:io';

import 'package:intl/intl.dart';

import 'package:charis_student_care/data/database/app_database.dart';

/// Creates a consistent copy of the live SQLite database while the app is open.
class DatabaseBackupService {
  DatabaseBackupService(this._db);

  final AppDatabase _db;

  /// Suggested backup filename, e.g. `charis_backup_2026-09-08.db`.
  static String suggestedFileName([DateTime? now]) {
    final stamp = DateFormat('yyyy-MM-dd').format(now ?? DateTime.now());
    return 'charis_backup_$stamp.db';
  }

  /// Writes a consistent snapshot to [destPath] using SQLite `VACUUM INTO`.
  /// Replaces [destPath] if it already exists.
  Future<void> backupTo(String destPath) async {
    final dest = File(destPath);
    final parent = dest.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    if (await dest.exists()) {
      await dest.delete();
    }
    await _db.customStatement("VACUUM INTO '${_escapeSqlPath(dest.path)}'");
  }

  static String _escapeSqlPath(String path) {
    return path.replaceAll('\\', '/').replaceAll("'", "''");
  }
}
