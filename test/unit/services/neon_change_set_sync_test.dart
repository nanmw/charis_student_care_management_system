import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:charis_student_care/core/config/sync_folder_config.dart';
import 'package:charis_student_care/core/exceptions/sync_exception.dart';
import 'package:charis_student_care/core/utils/io_retry.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/change_sets_repository.dart';
import 'package:charis_student_care/data/repositories/sync_conflicts_repository.dart';
import 'package:charis_student_care/data/services/change_set_applier.dart';
import 'package:charis_student_care/data/services/change_set_sync_service.dart';
import 'package:charis_student_care/data/services/neon_change_set_transport.dart';
import 'package:charis_student_care/presentation/providers/database_provider.dart';
import 'package:charis_student_care/presentation/providers/sync_providers.dart';

void main() {
  group('parseNeonConnectionString', () {
    test('reads host, database, and decoded password', () {
      final endpoint = parseNeonConnectionString(
        'postgresql://user:p%40ss@ep-pooler.example.neon.tech:5432/neondb?sslmode=require&channel_binding=require',
      );

      expect(endpoint.username, 'user');
      expect(endpoint.password, 'p@ss');
      expect(endpoint.host, 'ep-pooler.example.neon.tech');
      expect(endpoint.port, 5432);
      expect(endpoint.database, 'neondb');
    });

    test('rejects a non-postgres URL', () {
      expect(
        () => parseNeonConnectionString('https://example.com/db'),
        throwsFormatException,
      );
    });
  });

  group('ChangeSetSyncService.syncWithRemote', () {
    late AppDatabase db;
    late ChangeSetsRepository changeSets;
    late MemoryChangeSetRemote remote;
    late int cursor;
    late ChangeSetSyncService service;

    setUp(() {
      db = AppDatabase.test();
      changeSets = ChangeSetsRepository(db);
      remote = MemoryChangeSetRemote();
      cursor = 0;
      service = ChangeSetSyncService(
        changeSetsRepo: changeSets,
        syncConflictsRepo: SyncConflictsRepository(db),
        loadConfig: () async => SyncFolderConfig(
          deviceId: 'device-a',
          neonConnectionString: 'postgresql://user:secret@example.neon.tech/neondb',
          lastPulledSeq: cursor,
        ),
        saveLastPulledSeq: (seq) async {
          cursor = seq;
        },
        openRemote: (_) => remote,
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('pushes a local change-set once', () async {
      await changeSets.insertChangeSetRaw(
        id: 'local-1',
        table: 'classes',
        recordId: '1',
        operation: 'UPDATE',
        payload: '{"name":"Year 1"}',
        timestamp: DateTime.utc(2026, 3, 1),
        userId: 'u1',
        version: 1,
        deviceId: 'device-a',
      );

      final applier = ChangeSetApplier(db);
      final first = await service.syncWithRemote(
        tryApply: applier.tryApply,
      );
      final second = await service.syncWithRemote(
        tryApply: applier.tryApply,
      );

      expect(first, 0);
      expect(second, 0);
      expect(remote.pushCalls, 1);
      expect(remote.pushedIds, ['local-1']);
      expect(remote.rows, hasLength(1));
      final stored = await changeSets.getUnpushedChangeSets();
      expect(stored, isEmpty);
      expect(cursor, 1);
    });

    test('pulls a remote change-set and applies it once', () async {
      remote.addIncoming(
        ChangeSetRecord(
          id: 'remote-class',
          table: 'classes',
          recordId: 'remote-class-1',
          operation: 'INSERT',
          payload: '{"name":"Neon Year","sortOrder":9}',
          timestamp: DateTime.utc(2026, 4, 1),
          userId: 'u2',
          version: 1,
          deviceId: 'device-b',
        ),
      );

      final applier = ChangeSetApplier(db);
      final applied = await service.syncWithRemote(
        tryApply: applier.tryApply,
      );
      final again = await service.syncWithRemote(
        tryApply: applier.tryApply,
      );

      expect(applied, 1);
      expect(again, 0);
      expect(remote.pushCalls, 0);
      final classes = await db.select(db.classes).get();
      expect(classes.map((row) => row.name), contains('Neon Year'));
      final seen = await (db.select(db.changeSets)
            ..where((t) => t.id.equals('remote-class')))
          .getSingle();
      expect(seen.remotePushed, isTrue);
      expect(cursor, 1);
    });

    test('does not advance the cursor past a change-set that must be retried', () async {
      remote.addIncoming(
        ChangeSetRecord(
          id: 'blocked',
          table: 'classes',
          recordId: 'blocked-1',
          operation: 'INSERT',
          payload: '{"name":""}',
          timestamp: DateTime.utc(2026, 4, 1),
          userId: 'u2',
          version: 1,
          deviceId: 'device-b',
        ),
      );
      remote.addIncoming(
        ChangeSetRecord(
          id: 'later',
          table: 'classes',
          recordId: 'later-1',
          operation: 'INSERT',
          payload: '{"name":"Neon Year","sortOrder":9}',
          timestamp: DateTime.utc(2026, 4, 2),
          userId: 'u2',
          version: 1,
          deviceId: 'device-b',
        ),
      );

      final applied = await service.syncWithRemote(
        tryApply: ChangeSetApplier(db).tryApply,
      );

      expect(applied, 0);
      expect(cursor, 0);
      final classes = await db.select(db.classes).get();
      expect(classes.map((row) => row.name), isNot(contains('Neon Year')));
    });

    test('leaves local rows unpushed when the connection fails', () async {
      await changeSets.insertChangeSetRaw(
        id: 'local-2',
        table: 'classes',
        recordId: '2',
        operation: 'UPDATE',
        payload: '{"name":"Year 2"}',
        timestamp: DateTime.utc(2026, 3, 2),
        userId: 'u1',
        version: 1,
        deviceId: 'device-a',
      );
      remote.error = const SocketException('Connection failed');

      await expectLater(
        service.syncWithRemote(tryApply: ChangeSetApplier(db).tryApply),
        throwsA(isA<SocketException>()),
      );

      final unpushed = await changeSets.getUnpushedChangeSets();
      expect(unpushed.map((row) => row.id), ['local-2']);
      expect(cursor, 0);
      expect(
        userFacingSyncError(const SocketException('Connection failed')),
        contains('sync database'),
      );
    });

    test('throws when no connection string is saved', () async {
      final unconfigured = ChangeSetSyncService(
        changeSetsRepo: changeSets,
        syncConflictsRepo: SyncConflictsRepository(db),
        loadConfig: () async => SyncFolderConfig(deviceId: 'device-a'),
        saveLastPulledSeq: (_) async {},
        openRemote: (_) => remote,
      );

      await expectLater(
        unconfigured.syncWithRemote(tryApply: ChangeSetApplier(db).tryApply),
        throwsA(isA<SyncException>()),
      );
    });
  });

  group('runChangeSetFullSync connection failure', () {
    test('sets the sync error status', () async {
      final db = AppDatabase.test();
      final remote = MemoryChangeSetRemote()
        ..error = const SocketException('Connection failed');
      final service = ChangeSetSyncService(
        changeSetsRepo: ChangeSetsRepository(db),
        syncConflictsRepo: SyncConflictsRepository(db),
        loadConfig: () async => SyncFolderConfig(
          deviceId: 'device-a',
          neonConnectionString: 'postgresql://user:secret@example.neon.tech/neondb',
        ),
        saveLastPulledSeq: (_) async {},
        openRemote: (_) => remote,
      );
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          changeSetSyncServiceProvider.overrideWithValue(service),
        ],
      );
      final runSync = Provider<Future<int> Function()>((ref) {
        return () => runChangeSetFullSync(ref);
      });

      await expectLater(
        container.read(runSync)(),
        throwsA(isA<SocketException>()),
      );

      final status = container.read(changeSetSyncStatusProvider);
      expect(status.hasError, isTrue);
      expect(status.isSyncing, isFalse);
      expect(status.lastError, contains('sync database'));

      await db.close();
      container.dispose();
    });
  });
}

class MemoryChangeSetRemote implements ChangeSetRemote {
  final List<RemoteChangeSet> rows = [];
  final List<String> pushedIds = [];
  int pushCalls = 0;
  int _nextSeq = 0;
  Object? error;

  void addIncoming(ChangeSetRecord record) {
    _nextSeq++;
    rows.add(RemoteChangeSet(seq: _nextSeq, record: record));
  }

  @override
  Future<void> push(List<ChangeSetRecord> incoming) async {
    pushCalls++;
    if (error != null) throw error!;
    for (final row in incoming) {
      pushedIds.add(row.id);
      if (rows.any((existing) => existing.record.id == row.id)) continue;
      _nextSeq++;
      rows.add(RemoteChangeSet(seq: _nextSeq, record: row));
    }
  }

  @override
  Future<List<RemoteChangeSet>> pullAfter(
    int afterSeq, {
    int limit = 200,
  }) async {
    if (error != null) throw error!;
    return rows.where((row) => row.seq > afterSeq).take(limit).toList();
  }

  @override
  Future<void> close() async {}
}
