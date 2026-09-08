import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:charis_student_care/data/database/database_file.dart';

void main() {
  late Directory documentsDir;
  late Directory supportDir;

  setUp(() {
    DatabaseFile.resetLiveFileForTest();
    documentsDir = Directory.systemTemp.createTempSync('charis_docs_');
    supportDir = Directory.systemTemp.createTempSync('charis_support_');
  });

  tearDown(() {
    DatabaseFile.resetLiveFileForTest();
    if (documentsDir.existsSync()) {
      documentsDir.deleteSync(recursive: true);
    }
    if (supportDir.existsSync()) {
      supportDir.deleteSync(recursive: true);
    }
  });

  File docsDb() => File(p.join(documentsDir.path, DatabaseFile.fileName));
  File supportDb() => File(p.join(supportDir.path, DatabaseFile.fileName));

  test('migrates Documents db and wal/shm into Support then renames source',
      () async {
    await docsDb().writeAsString('main-db');
    await File('${docsDb().path}-wal').writeAsString('wal-data');
    await File('${docsDb().path}-shm').writeAsString('shm-data');

    final live = await DatabaseFile.resolveLiveFile(
      supportDir: supportDir,
      documentsDir: documentsDir,
    );

    expect(live.path, supportDb().path);
    expect(await supportDb().readAsString(), 'main-db');
    expect(await File('${supportDb().path}-wal').readAsString(), 'wal-data');
    expect(await File('${supportDb().path}-shm').readAsString(), 'shm-data');

    expect(docsDb().existsSync(), isFalse);
    expect(File('${docsDb().path}.migrated').existsSync(), isTrue);
    expect(
      await File('${docsDb().path}.migrated').readAsString(),
      'main-db',
    );
    expect(File('${docsDb().path}-wal.migrated').existsSync(), isTrue);
    expect(File('${docsDb().path}-shm.migrated').existsSync(), isTrue);
    expect(DatabaseFile.liveFile?.path, supportDb().path);
  });

  test('skips migrate when Support db already exists', () async {
    await docsDb().writeAsString('old-docs');
    await supportDb().writeAsString('existing-support');

    final live = await DatabaseFile.resolveLiveFile(
      supportDir: supportDir,
      documentsDir: documentsDir,
    );

    expect(live.path, supportDb().path);
    expect(await supportDb().readAsString(), 'existing-support');
    expect(docsDb().existsSync(), isTrue);
    expect(await docsDb().readAsString(), 'old-docs');
    expect(File('${docsDb().path}.migrated').existsSync(), isFalse);
  });

  test('creates Support path when neither file exists', () async {
    final live = await DatabaseFile.resolveLiveFile(
      supportDir: supportDir,
      documentsDir: documentsDir,
    );

    expect(live.path, supportDb().path);
    expect(supportDb().existsSync(), isFalse);
    expect(docsDb().existsSync(), isFalse);
    expect(DatabaseFile.liveFile?.path, supportDb().path);
  });

  test('falls back to Documents when migrate copy fails', () async {
    await docsDb().writeAsString('docs-only');
    // A file with the same name as the support directory blocks mkdir/copy.
    final blocked = File(supportDir.path);
    supportDir.deleteSync(recursive: true);
    await blocked.writeAsString('not-a-directory');

    final live = await DatabaseFile.resolveLiveFile(
      supportDir: Directory(supportDir.path),
      documentsDir: documentsDir,
    );

    expect(live.path, docsDb().path);
    expect(await docsDb().readAsString(), 'docs-only');
    expect(File('${docsDb().path}.migrated').existsSync(), isFalse);

    await blocked.delete();
  });
}
