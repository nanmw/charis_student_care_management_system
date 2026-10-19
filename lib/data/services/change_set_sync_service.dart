import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:charis_student_care/core/config/sync_folder_config.dart';
import 'package:charis_student_care/core/exceptions/sync_exception.dart';
import 'package:charis_student_care/core/utils/io_retry.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/change_sets_repository.dart';
import 'package:charis_student_care/data/repositories/sync_conflicts_repository.dart';
import 'package:charis_student_care/data/services/change_set_remote.dart';
import 'package:charis_student_care/data/services/neon_change_set_transport.dart';

export 'package:charis_student_care/data/services/change_set_remote.dart'
    show ChangeSetRecord, ChangeSetRemote, RemoteChangeSet;

/// Export format: one JSON file per device. Array of change-set objects.
Map<String, dynamic> changeSetToJson(ChangeSet cs) {
  return {
    'id': cs.id,
    'table': cs.table,
    'recordId': cs.recordId,
    'operation': cs.operation,
    'payload': cs.payload,
    'timestamp': cs.timestamp.toUtc().toIso8601String(),
    'userId': cs.userId,
    'version': cs.version,
    'deviceId': cs.deviceId,
  };
}

ChangeSetRecord changeSetRecordFromLocal(ChangeSet cs) {
  return ChangeSetRecord(
    id: cs.id,
    table: cs.table,
    recordId: cs.recordId,
    operation: cs.operation,
    payload: cs.payload,
    timestamp: cs.timestamp.toUtc(),
    userId: cs.userId,
    version: cs.version,
    deviceId: cs.deviceId,
  );
}

/// Result of applying a single change-set: applied, conflict, or skipped.
sealed class ApplyResult {}

class ApplyResultApplied extends ApplyResult {}

/// Change-set was not applied. Permanent skips are marked seen; temporary skips retry.
class ApplyResultSkipped extends ApplyResult {
  /// When [permanent] is true, the change-set is marked seen without applying
  /// (corrupt/unsupported). Temporary skips (missing deps) are retried.
  ApplyResultSkipped({this.reason, this.permanent = false});
  final String? reason;
  final bool permanent;
}

class ApplyResultConflict extends ApplyResult {
  ApplyResultConflict({
    required this.changeSetId,
    required this.tableName,
    required this.recordId,
    required this.incomingPayload,
    required this.localSnapshot,
    required this.sourceDeviceId,
  });

  final String changeSetId;
  final String tableName;
  final String recordId;
  final String incomingPayload;
  final String localSnapshot;
  final String sourceDeviceId;
}

/// Sync service: export this device's change-sets to the sync folder,
/// import others' change-sets from the sync folder and apply them.
class ChangeSetSyncService {
  ChangeSetSyncService({
    required ChangeSetsRepository changeSetsRepo,
    required SyncConflictsRepository syncConflictsRepo,
    Future<SyncFolderConfig> Function()? loadConfig,
    Future<Directory> Function()? exportHashCacheDir,
    Future<void> Function(int seq)? saveLastPulledSeq,
    ChangeSetRemote Function(String connectionString)? openRemote,
  })  : _changeSetsRepo = changeSetsRepo,
        _syncConflictsRepo = syncConflictsRepo,
        _loadConfig = loadConfig ?? SyncFolderConfig.load,
        _exportHashCacheDir = exportHashCacheDir ?? _defaultExportHashCacheDir,
        _saveLastPulledSeq = saveLastPulledSeq ?? SyncFolderConfig.saveLastPulledSeq,
        _openRemote = openRemote ?? NeonChangeSetTransport.new;

  final ChangeSetsRepository _changeSetsRepo;
  final SyncConflictsRepository _syncConflictsRepo;
  final Future<SyncFolderConfig> Function() _loadConfig;
  final Future<Directory> Function() _exportHashCacheDir;
  final Future<void> Function(int seq) _saveLastPulledSeq;
  final ChangeSetRemote Function(String connectionString) _openRemote;

  static const int _pushBatchSize = 100;
  static const int _pullBatchSize = 200;

  static const String _deviceFilePrefix = 'device_';
  static const String _deviceFileSuffix = '.json';
  static const JsonEncoder _exportEncoder = JsonEncoder.withIndent('  ');

  static Future<Directory> _defaultExportHashCacheDir() async {
    final supportDir = await getApplicationSupportDirectory();
    return Directory(p.join(supportDir.path, 'export_hash_cache'));
  }

  static String exportContentHash(String content) {
    return sha256.convert(utf8.encode(content)).toString();
  }

  static Future<File> exportHashCacheFileFor({
    required Directory cacheDir,
    required String deviceId,
  }) async {
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return File(p.join(cacheDir.path, 'last_export_hash_$deviceId.txt'));
  }

  /// Writes [content] to [file] when [hashCacheFile] hash differs. Avoids reading
  /// from the sync folder (e.g. OneDrive) to detect unchanged exports.
  ///
  /// Uses a sibling `.tmp` file then replace so readers never see a partial JSON
  /// file. Retries on brief OneDrive / OS file locks.
  static Future<bool> writeExportIfChanged(
    File file,
    String content, {
    required File hashCacheFile,
  }) async {
    final hash = exportContentHash(content);
    if (await hashCacheFile.exists()) {
      final cached = (await hashCacheFile.readAsString()).trim();
      if (cached == hash) return false;
    }
    await retryOnTransientIo(() async {
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(content, flush: true);
      if (await file.exists()) {
        await file.delete();
      }
      await temp.rename(file.path);
    });
    await hashCacheFile.writeAsString(hash);
    return true;
  }

  /// Export this device's change-sets to the sync folder.
  /// Returns true if the device JSON file was written, false if skipped or no folder.
  Future<bool> export() async {
    final config = await _loadConfig();
    await _changeSetsRepo.retagLegacyChangeSetsTo(config.deviceId);
    final path = config.syncFolderPath;
    if (path == null || path.isEmpty) return false;

    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final list = await _changeSetsRepo.getChangeSetsByDevice(config.deviceId);
    final jsonList = list.map(changeSetToJson).toList();
    final content = _exportEncoder.convert(jsonList);
    final file = File(p.join(path, '$_deviceFilePrefix${config.deviceId}$_deviceFileSuffix'));
    final cacheDir = await _exportHashCacheDir();
    final hashCacheFile = await exportHashCacheFileFor(
      cacheDir: cacheDir,
      deviceId: config.deviceId,
    );
    return writeExportIfChanged(
      file,
      content,
      hashCacheFile: hashCacheFile,
    );
  }

  static String deviceFileNameFor(String deviceId) =>
      '$_deviceFilePrefix$deviceId$_deviceFileSuffix';

  static bool isDeviceFileFor(String fileName, String deviceId) {
    if (!fileName.startsWith(_deviceFilePrefix) ||
        !fileName.endsWith(_deviceFileSuffix) ||
        deviceId.isEmpty) {
      return false;
    }
    final core = fileName.substring(
      _deviceFilePrefix.length,
      fileName.length - _deviceFileSuffix.length,
    );
    return core == deviceId || core.startsWith('$deviceId-');
  }

  /// List device_*.json files in the sync folder.
  Future<List<File>> _listDeviceFiles(String syncFolderPath) async {
    final dir = Directory(syncFolderPath);
    if (!await dir.exists()) return [];
    final files = <File>[];
    await for (final entity in dir.list()) {
      if (entity is File) {
        final name = p.basename(entity.path);
        if (name.startsWith(_deviceFilePrefix) && name.endsWith(_deviceFileSuffix)) {
          files.add(entity);
        }
      }
    }
    return files;
  }

  /// Read and parse a device JSON file. Returns empty list on parse error.
  Future<List<ChangeSetRecord>> _readDeviceFile(File file) async {
    try {
      final content = await retryOnTransientIo(() => file.readAsString());
      final decoded = jsonDecode(content);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(ChangeSetRecord.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Import change-sets from the sync folder: read all device_*.json files,
  /// merge by id, sort by timestamp, then try to apply any not already in local DB.
  /// Uses [tryApply] (returns [ApplyResult]); on conflict, records the change-set as seen and stores conflict.
  /// An exception from one change-set is recorded the same way and does not stop the rest.
  Future<int> import({Future<ApplyResult> Function(ChangeSetRecord)? tryApply}) async {
    final config = await _loadConfig();
    final path = config.syncFolderPath;
    if (path == null || path.isEmpty) return 0;
    if (tryApply == null) return 0;

    final ownFileName = deviceFileNameFor(config.deviceId);
    final files = await _listDeviceFiles(path);
    final allRecords = <String, ChangeSetRecord>{};
    for (final file in files) {
      final basename = p.basename(file.path);
      if (basename == ownFileName || isDeviceFileFor(basename, config.deviceId)) {
        continue;
      }
      final list = await _readDeviceFile(file);
      for (final r in list) {
        allRecords[r.id] = r;
      }
    }
    final sorted = allRecords.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    int applied = 0;
    for (final record in sorted) {
      final exists = await _changeSetsRepo.hasChangeSet(record.id);
      if (!exists) {
        final ApplyResult result;
        try {
          result = await tryApply(record);
        } catch (e) {
          await _markChangeSetSeen(record);
          await _syncConflictsRepo.insert(
            changeSetId: record.id,
            tableName: record.table,
            recordId: record.recordId,
            incomingPayload: record.payload,
            localSnapshot: jsonEncode({'error': e.toString()}),
            sourceDeviceId: record.deviceId,
          );
          continue;
        }
        if (result is ApplyResultSkipped) {
          if (result.permanent) {
            await _markChangeSetSeen(record);
          }
          continue;
        }
        if (result is ApplyResultConflict) {
          await _markChangeSetSeen(record);
          await _syncConflictsRepo.insert(
            changeSetId: result.changeSetId,
            tableName: result.tableName,
            recordId: result.recordId,
            incomingPayload: result.incomingPayload,
            localSnapshot: result.localSnapshot,
            sourceDeviceId: result.sourceDeviceId,
          );
        } else {
          applied++;
        }
      }
    }
    return applied;
  }

  Future<void> _markChangeSetSeen(ChangeSetRecord record) {
    return _changeSetsRepo.insertChangeSetRaw(
      id: record.id,
      table: record.table,
      recordId: record.recordId,
      operation: record.operation,
      payload: record.payload,
      timestamp: record.timestamp,
      userId: record.userId,
      version: record.version,
      deviceId: record.deviceId,
    );
  }

  /// Whether this PC has a Neon connection string saved.
  Future<bool> remoteConfigured() async {
    final config = await _loadConfig();
    return config.hasNeonConnection;
  }

  /// Push unpushed local change-sets, then pull and apply remote rows.
  ///
  /// Returns how many remote change-sets were newly applied.
  /// Throws [SyncException] when no connection string is saved.
  Future<int> syncWithRemote({
    required Future<ApplyResult> Function(ChangeSetRecord) tryApply,
  }) async {
    final config = await _loadConfig();
    final connectionString = config.neonConnectionString?.trim();
    if (connectionString == null || connectionString.isEmpty) {
      throw SyncException('Neon connection string is not set');
    }

    await _changeSetsRepo.retagLegacyChangeSetsTo(config.deviceId);
    final remote = _openRemote(connectionString);
    try {
      await _pushUnpushed(remote);
      return await _pullAndApply(
        remote,
        startSeq: config.lastPulledSeq,
        tryApply: tryApply,
      );
    } finally {
      await remote.close();
    }
  }

  Future<void> _pushUnpushed(ChangeSetRemote remote) async {
    while (true) {
      final rows = await _changeSetsRepo.getUnpushedChangeSets(
        limit: _pushBatchSize,
      );
      if (rows.isEmpty) return;
      await remote.push(rows.map(changeSetRecordFromLocal).toList());
      await _changeSetsRepo.markRemotePushed(rows.map((row) => row.id));
      if (rows.length < _pushBatchSize) return;
    }
  }

  Future<int> _pullAndApply(
    ChangeSetRemote remote, {
    required int startSeq,
    required Future<ApplyResult> Function(ChangeSetRecord) tryApply,
  }) async {
    var cursor = startSeq;
    var applied = 0;

    while (true) {
      final rows = await remote.pullAfter(cursor, limit: _pullBatchSize);
      if (rows.isEmpty) break;

      var blocked = false;
      for (final row in rows) {
        final record = row.record;
        final exists = await _changeSetsRepo.hasChangeSet(record.id);
        if (exists) {
          cursor = row.seq;
          continue;
        }

        final ApplyResult result;
        try {
          result = await tryApply(record);
        } catch (e) {
          await _markChangeSetSeen(record);
          await _syncConflictsRepo.insert(
            changeSetId: record.id,
            tableName: record.table,
            recordId: record.recordId,
            incomingPayload: record.payload,
            localSnapshot: jsonEncode({'error': e.toString()}),
            sourceDeviceId: record.deviceId,
          );
          await _changeSetsRepo.markRemotePushed([record.id]);
          cursor = row.seq;
          continue;
        }

        if (result is ApplyResultSkipped && !result.permanent) {
          blocked = true;
          break;
        }
        if (result is ApplyResultSkipped && result.permanent) {
          await _markChangeSetSeen(record);
        } else if (result is ApplyResultConflict) {
          await _markChangeSetSeen(record);
          await _syncConflictsRepo.insert(
            changeSetId: result.changeSetId,
            tableName: result.tableName,
            recordId: result.recordId,
            incomingPayload: result.incomingPayload,
            localSnapshot: result.localSnapshot,
            sourceDeviceId: result.sourceDeviceId,
          );
        }
        await _changeSetsRepo.markRemotePushed([record.id]);
        if (result is ApplyResultApplied) applied++;
        cursor = row.seq;
      }

      await _saveLastPulledSeq(cursor);
      if (blocked || rows.length < _pullBatchSize) break;
    }

    return applied;
  }
}
