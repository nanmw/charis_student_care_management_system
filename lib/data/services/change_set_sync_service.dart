import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:charis_student_care/core/config/sync_folder_config.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/change_sets_repository.dart';
import 'package:charis_student_care/data/repositories/sync_conflicts_repository.dart';

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

/// Parsed row from imported JSON (before inserting into DB).
class ChangeSetRecord {
  const ChangeSetRecord({
    required this.id,
    required this.table,
    required this.recordId,
    required this.operation,
    required this.payload,
    required this.timestamp,
    required this.userId,
    required this.version,
    required this.deviceId,
  });

  final String id;
  final String table;
  final String recordId;
  final String operation;
  final String payload;
  final DateTime timestamp;
  final String userId;
  final int version;
  final String deviceId;

  static ChangeSetRecord fromJson(Map<String, dynamic> json) {
    return ChangeSetRecord(
      id: json['id'] as String,
      table: json['table'] as String,
      recordId: json['recordId'] as String,
      operation: json['operation'] as String,
      payload: json['payload'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      userId: json['userId'] as String,
      version: json['version'] as int,
      deviceId: json['deviceId'] as String,
    );
  }
}

/// Result of applying a single change-set: either applied or conflict (critical field).
sealed class ApplyResult {}

class ApplyResultApplied extends ApplyResult {}

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
  })  : _changeSetsRepo = changeSetsRepo,
        _syncConflictsRepo = syncConflictsRepo;

  final ChangeSetsRepository _changeSetsRepo;
  final SyncConflictsRepository _syncConflictsRepo;

  static const String _deviceFilePrefix = 'device_';
  static const String _deviceFileSuffix = '.json';

  /// Export this device's change-sets to the sync folder. No-op if sync folder not set.
  Future<void> export() async {
    final config = await SyncFolderConfig.load();
    final path = config.syncFolderPath;
    if (path == null || path.isEmpty) return;

    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final list = await _changeSetsRepo.getChangeSetsByDevice(config.deviceId);
    final jsonList = list.map(changeSetToJson).toList();
    final file = File(p.join(path, '$_deviceFilePrefix${config.deviceId}$_deviceFileSuffix'));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(jsonList),
      flush: true,
    );
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
      final content = await file.readAsString();
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
  Future<int> import({Future<ApplyResult> Function(ChangeSetRecord)? tryApply}) async {
    final config = await SyncFolderConfig.load();
    final path = config.syncFolderPath;
    if (path == null || path.isEmpty) return 0;
    if (tryApply == null) return 0;

    final files = await _listDeviceFiles(path);
    final allRecords = <String, ChangeSetRecord>{};
    for (final file in files) {
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
        final result = await tryApply(record);
        if (result is ApplyResultConflict) {
          await _changeSetsRepo.insertChangeSetRaw(
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
}
