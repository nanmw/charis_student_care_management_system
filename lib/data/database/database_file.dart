import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Live SQLite file location: Application Support (AppData on Windows).
///
/// Older installs stored the file in Documents (often OneDrive). On first
/// launch, [resolveLiveFile] copies that file into Support and renames the
/// Documents copy so it is no longer the live database.
class DatabaseFile {
  DatabaseFile._();

  static const String fileName = 'charis_student_care.db';
  static const String migratedSuffix = '.migrated';
  static const List<String> sidecarSuffixes = ['-wal', '-shm'];

  static File? _liveFile;

  /// Last path chosen by [resolveLiveFile], if any.
  static File? get liveFile => _liveFile;

  /// Clears cached path (unit tests only).
  static void resetLiveFileForTest() {
    _liveFile = null;
  }

  /// Support-dir path for a new or already-migrated database (does not migrate).
  static Future<File> supportFile({Directory? supportDir}) async {
    final dir = supportDir ?? await getApplicationSupportDirectory();
    return File(p.join(dir.path, fileName));
  }

  /// Documents-dir path used by older installs.
  static Future<File> documentsFile({Directory? documentsDir}) async {
    final dir = documentsDir ?? await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, fileName));
  }

  /// Resolves the live database file, migrating from Documents when needed.
  ///
  /// If [supportDir] already has [fileName], that file is used.
  /// Else if Documents has [fileName], it is copied (with WAL/SHM) then renamed
  /// aside. On copy failure, Documents is used for this session.
  /// Else a new file will be created in Support.
  static Future<File> resolveLiveFile({
    Directory? supportDir,
    Directory? documentsDir,
  }) async {
    final support = supportDir ?? await getApplicationSupportDirectory();
    final documents = documentsDir ?? await getApplicationDocumentsDirectory();
    final dest = File(p.join(support.path, fileName));
    final source = File(p.join(documents.path, fileName));

    if (await dest.exists()) {
      _liveFile = dest;
      return dest;
    }

    if (await source.exists()) {
      try {
        await migrateDocumentsToSupport(
          documentsDir: documents,
          supportDir: support,
        );
        _liveFile = dest;
        return dest;
      } catch (_) {
        _liveFile = source;
        return source;
      }
    }

    if (!await support.exists()) {
      await support.create(recursive: true);
    }
    _liveFile = dest;
    return dest;
  }

  /// Copies the Documents database (and sidecars) into Support, then renames
  /// the Documents files to `*.migrated`.
  static Future<void> migrateDocumentsToSupport({
    required Directory documentsDir,
    required Directory supportDir,
  }) async {
    if (!await supportDir.exists()) {
      await supportDir.create(recursive: true);
    }

    final sourceDb = File(p.join(documentsDir.path, fileName));
    if (!await sourceDb.exists()) {
      throw StateError('No Documents database to migrate');
    }

    for (final src in relatedFiles(sourceDb)) {
      if (!await src.exists()) continue;
      final dest = File(p.join(supportDir.path, p.basename(src.path)));
      await src.copy(dest.path);
    }

    for (final src in relatedFiles(sourceDb)) {
      if (!await src.exists()) continue;
      await _renameAside(src);
    }
  }

  /// The `.db` file plus `-wal` and `-shm` companions.
  static List<File> relatedFiles(File dbFile) {
    return [
      dbFile,
      for (final suffix in sidecarSuffixes) File('${dbFile.path}$suffix'),
    ];
  }

  static Future<void> _renameAside(File source) async {
    final aside = File('${source.path}$migratedSuffix');
    if (await aside.exists()) {
      await aside.delete();
    }
    await source.rename(aside.path);
  }
}
