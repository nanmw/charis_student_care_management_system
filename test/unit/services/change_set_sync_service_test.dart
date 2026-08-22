import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:charis_student_care/core/config/sync_folder_config.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/change_sets_repository.dart';
import 'package:charis_student_care/data/repositories/sync_conflicts_repository.dart';
import 'package:charis_student_care/data/services/change_set_sync_service.dart';

void main() {
  group('ChangeSetSyncService.writeExportIfChanged', () {
    late Directory tempDir;
    late Directory hashCacheDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('charis_export_test_');
      hashCacheDir =
          await Directory.systemTemp.createTemp('charis_export_hash_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      if (await hashCacheDir.exists()) {
        await hashCacheDir.delete(recursive: true);
      }
    });

    Future<File> hashCacheFile() async {
      return ChangeSetSyncService.exportHashCacheFileFor(
        cacheDir: hashCacheDir,
        deviceId: 'test-device',
      );
    }

    test('writes new file and returns true', () async {
      final file = File('${tempDir.path}/device_test.json');
      const content = '[]';

      final wrote = await ChangeSetSyncService.writeExportIfChanged(
        file,
        content,
        hashCacheFile: await hashCacheFile(),
      );

      expect(wrote, isTrue);
      expect(await file.readAsString(), content);
    });

    test('skips write when hash unchanged and returns false', () async {
      final file = File('${tempDir.path}/device_test.json');
      const content = '[\n  {"id": "a"}\n]';
      await file.writeAsString(content);
      final cache = await hashCacheFile();
      await cache.writeAsString(ChangeSetSyncService.exportContentHash(content));
      final before = await file.lastModified();

      await Future<void>.delayed(const Duration(milliseconds: 20));

      final wrote = await ChangeSetSyncService.writeExportIfChanged(
        file,
        content,
        hashCacheFile: cache,
      );

      expect(wrote, isFalse);
      expect(await file.lastModified(), before);
    });

    test('writes when content differs', () async {
      final file = File('${tempDir.path}/device_test.json');
      await file.writeAsString('[]');
      final cache = await hashCacheFile();
      await cache.writeAsString(ChangeSetSyncService.exportContentHash('[]'));

      final wrote = await ChangeSetSyncService.writeExportIfChanged(
        file,
        '[\n  {"id": "b"}\n]',
        hashCacheFile: cache,
      );

      expect(wrote, isTrue);
      expect(await file.readAsString(), '[\n  {"id": "b"}\n]');
    });

    test('leaves no sibling .tmp after successful write', () async {
      final file = File('${tempDir.path}/device_test.json');
      final temp = File('${file.path}.tmp');

      final wrote = await ChangeSetSyncService.writeExportIfChanged(
        file,
        '[{"id":"c"}]',
        hashCacheFile: await hashCacheFile(),
      );

      expect(wrote, isTrue);
      expect(await file.exists(), isTrue);
      expect(await temp.exists(), isFalse);
      expect(await file.readAsString(), '[{"id":"c"}]');
    });

    test('replaces existing file atomically', () async {
      final file = File('${tempDir.path}/device_test.json');
      await file.writeAsString('old');
      final cache = await hashCacheFile();
      await cache.writeAsString(ChangeSetSyncService.exportContentHash('old'));

      final wrote = await ChangeSetSyncService.writeExportIfChanged(
        file,
        'new-content',
        hashCacheFile: cache,
      );

      expect(wrote, isTrue);
      expect(await file.readAsString(), 'new-content');
      expect(await File('${file.path}.tmp').exists(), isFalse);
    });
  });

  group('ChangeSetSyncService.export', () {
    late AppDatabase db;
    late Directory tempDir;
    late Directory hashCacheDir;
    late ChangeSetSyncService service;
    const deviceId = 'device-export-test';

    setUp(() async {
      db = AppDatabase.test();
      tempDir = await Directory.systemTemp.createTemp('charis_export_svc_test_');
      hashCacheDir =
          await Directory.systemTemp.createTemp('charis_export_svc_hash_test_');
      service = ChangeSetSyncService(
        changeSetsRepo: ChangeSetsRepository(db),
        syncConflictsRepo: SyncConflictsRepository(db),
        loadConfig: () async => SyncFolderConfig(
          syncFolderPath: tempDir.path,
          deviceId: deviceId,
        ),
        exportHashCacheDir: () async => hashCacheDir,
      );
    });

    tearDown(() async {
      await db.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      if (await hashCacheDir.exists()) {
        await hashCacheDir.delete(recursive: true);
      }
    });

    test('export skips rewrite when change-sets unchanged', () async {
      final first = await service.export();
      expect(first, isTrue);

      final file = File('${tempDir.path}/device_$deviceId.json');
      final before = await file.lastModified();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final second = await service.export();

      expect(second, isFalse);
      expect(await file.lastModified(), before);
    });

    test('export writes when a new change-set is added', () async {
      await service.export();

      await db.into(db.changeSets).insert(
            ChangeSetsCompanion.insert(
              id: 'cs-export-new',
              table: 'students',
              recordId: '99',
              operation: 'INSERT',
              payload: '{}',
              userId: 'user-a',
              version: 1,
              deviceId: deviceId,
            ),
          );

      final wrote = await service.export();
      expect(wrote, isTrue);
    });
  });

  group('ChangeSetSyncService.import', () {
    late AppDatabase db;
    late Directory tempDir;
    late ChangeSetSyncService service;
    const localDeviceId = 'local-device';
    const remoteDeviceId = 'remote-device';

    setUp(() async {
      db = AppDatabase.test();
      tempDir = await Directory.systemTemp.createTemp('charis_import_svc_test_');
      service = ChangeSetSyncService(
        changeSetsRepo: ChangeSetsRepository(db),
        syncConflictsRepo: SyncConflictsRepository(db),
        loadConfig: () async => SyncFolderConfig(
          syncFolderPath: tempDir.path,
          deviceId: localDeviceId,
        ),
      );
    });

    tearDown(() async {
      await db.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('import skips own device file', () async {
      const ownOnlyId = 'cs-own-unseen';
      const ownLegacyOnlyId = 'cs-own-legacy-unseen';
      const remoteOnlyId = 'cs-remote-new';

      final ownFile = File(
        '${tempDir.path}/${ChangeSetSyncService.deviceFileNameFor(localDeviceId)}',
      );
      await ownFile.writeAsString(
        '[{"id":"$ownOnlyId","table":"students","recordId":"99","operation":"INSERT","payload":"{}","timestamp":"2026-01-01T00:00:00.000Z","userId":"user-a","version":1,"deviceId":"$localDeviceId"}]',
      );
      final ownLegacyFile = File(
        '${tempDir.path}/device_$localDeviceId-DESKTOP-LEGACY.json',
      );
      await ownLegacyFile.writeAsString(
        '[{"id":"$ownLegacyOnlyId","table":"students","recordId":"109","operation":"INSERT","payload":"{}","timestamp":"2026-01-01T12:00:00.000Z","userId":"user-a","version":1,"deviceId":"$localDeviceId"}]',
      );

      final remoteFile = File(
        '${tempDir.path}/${ChangeSetSyncService.deviceFileNameFor(remoteDeviceId)}',
      );
      await remoteFile.writeAsString(
        '[{"id":"$remoteOnlyId","table":"students","recordId":"2","operation":"INSERT","payload":"{}","timestamp":"2026-01-02T00:00:00.000Z","userId":"user-b","version":1,"deviceId":"$remoteDeviceId"}]',
      );

      final seen = <String>[];
      final applied = await service.import(
        tryApply: (record) async {
          seen.add(record.id);
          return ApplyResultApplied();
        },
      );

      expect(applied, 1);
      expect(seen, contains(remoteOnlyId));
      expect(seen, isNot(contains(ownOnlyId)));
      expect(seen, isNot(contains(ownLegacyOnlyId)));
    });
  });
}
