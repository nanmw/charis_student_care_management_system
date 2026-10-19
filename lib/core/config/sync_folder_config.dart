import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Bootstrap config for change-set sync: Neon connection, cursor, and device ID.
/// Stored in app support directory so it's available before the main DB is opened.
/// The connection string is a secret and must not be committed or shown in full.
class SyncFolderConfig {
  SyncFolderConfig({
    this.syncFolderPath,
    required this.deviceId,
    this.autoSyncOnRemoteChange = true,
    this.neonConnectionString,
    this.lastPulledSeq = 0,
  });

  final String? syncFolderPath;
  final String deviceId;
  final bool autoSyncOnRemoteChange;

  /// Pooled Neon connection string. Null until an admin saves one on this PC.
  final String? neonConnectionString;

  /// Highest remote `change_sets.seq` already pulled on this PC.
  final int lastPulledSeq;

  static const String _configFileName = 'charis_sync_config.json';
  static const _uuid = Uuid();

  bool get hasNeonConnection {
    final value = neonConnectionString?.trim();
    return value != null && value.isNotEmpty;
  }

  /// Loads config from disk. If file is missing, creates default with new deviceId and saves.
  static Future<SyncFolderConfig> load() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, _configFileName));
    if (!await file.exists()) {
      final deviceId = _uuid.v4();
      final config = SyncFolderConfig(syncFolderPath: null, deviceId: deviceId);
      await config._save(file);
      return config;
    }
    final content = await file.readAsString();
    try {
      final map = jsonDecode(content) as Map<String, dynamic>;
      return SyncFolderConfig(
        syncFolderPath: map['syncFolderPath'] as String?,
        deviceId: map['deviceId'] as String? ?? _uuid.v4(),
        autoSyncOnRemoteChange: map['autoSyncOnRemoteChange'] as bool? ?? true,
        neonConnectionString: map['neonConnectionString'] as String?,
        lastPulledSeq: _readSeq(map['lastPulledSeq']),
      );
    } catch (_) {
      final deviceId = _uuid.v4();
      final config = SyncFolderConfig(syncFolderPath: null, deviceId: deviceId);
      await config._save(file);
      return config;
    }
  }

  static int _readSeq(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  Future<void> _save(File file) async {
    final map = <String, dynamic>{
      'syncFolderPath': syncFolderPath,
      'deviceId': deviceId,
      'autoSyncOnRemoteChange': autoSyncOnRemoteChange,
      'neonConnectionString': neonConnectionString,
      'lastPulledSeq': lastPulledSeq,
    };
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(map));
  }

  static Future<void> _write(SyncFolderConfig config) async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, _configFileName));
    await config._save(file);
  }

  /// Saves the sync folder path. Load config, update path, write back.
  static Future<void> saveSyncFolderPath(String? path) async {
    final config = await load();
    await _write(
      SyncFolderConfig(
        syncFolderPath: path,
        deviceId: config.deviceId,
        autoSyncOnRemoteChange: config.autoSyncOnRemoteChange,
        neonConnectionString: config.neonConnectionString,
        lastPulledSeq: config.lastPulledSeq,
      ),
    );
  }

  /// Saves whether auto-sync should run while the app is open.
  static Future<void> saveAutoSyncOnRemoteChange(bool enabled) async {
    final config = await load();
    await _write(
      SyncFolderConfig(
        syncFolderPath: config.syncFolderPath,
        deviceId: config.deviceId,
        autoSyncOnRemoteChange: enabled,
        neonConnectionString: config.neonConnectionString,
        lastPulledSeq: config.lastPulledSeq,
      ),
    );
  }

  /// Saves the Neon connection string on this PC.
  ///
  /// Changing or clearing the string resets [lastPulledSeq] so the next sync
  /// reads the new database from the start. Saving the same string keeps the cursor.
  static Future<void> saveNeonConnectionString(String? value) async {
    final config = await load();
    final trimmed = value?.trim();
    final normalized = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    final changed = normalized != config.neonConnectionString;
    await _write(
      SyncFolderConfig(
        syncFolderPath: config.syncFolderPath,
        deviceId: config.deviceId,
        autoSyncOnRemoteChange: config.autoSyncOnRemoteChange,
        neonConnectionString: normalized,
        lastPulledSeq: changed ? 0 : config.lastPulledSeq,
      ),
    );
  }

  /// Saves the remote sequence cursor after a successful pull batch.
  static Future<void> saveLastPulledSeq(int seq) async {
    final config = await load();
    await _write(
      SyncFolderConfig(
        syncFolderPath: config.syncFolderPath,
        deviceId: config.deviceId,
        autoSyncOnRemoteChange: config.autoSyncOnRemoteChange,
        neonConnectionString: config.neonConnectionString,
        lastPulledSeq: seq,
      ),
    );
  }

  /// Returns device ID from config, creating and persisting one if missing.
  static Future<String> getOrCreateDeviceId() async {
    final config = await load();
    return config.deviceId;
  }
}
