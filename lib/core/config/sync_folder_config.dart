import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Bootstrap config for change-set sync: sync folder path and device ID.
/// Stored in app support directory so it's available before the main DB is opened.
class SyncFolderConfig {
  SyncFolderConfig({
    this.syncFolderPath,
    required this.deviceId,
    this.autoSyncOnRemoteChange = true,
  });

  final String? syncFolderPath;
  final String deviceId;
  final bool autoSyncOnRemoteChange;

  static const String _configFileName = 'charis_sync_config.json';
  static const _uuid = Uuid();

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
      );
    } catch (_) {
      final deviceId = _uuid.v4();
      final config = SyncFolderConfig(syncFolderPath: null, deviceId: deviceId);
      await config._save(file);
      return config;
    }
  }

  Future<void> _save(File file) async {
    final map = <String, dynamic>{
      'syncFolderPath': syncFolderPath,
      'deviceId': deviceId,
      'autoSyncOnRemoteChange': autoSyncOnRemoteChange,
    };
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(map));
  }

  /// Saves the sync folder path. Load config, update path, write back.
  static Future<void> saveSyncFolderPath(String? path) async {
    final config = await load();
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, _configFileName));
    final updated = SyncFolderConfig(
      syncFolderPath: path,
      deviceId: config.deviceId,
      autoSyncOnRemoteChange: config.autoSyncOnRemoteChange,
    );
    await updated._save(file);
  }

  /// Saves whether auto-sync should run when sync files change.
  static Future<void> saveAutoSyncOnRemoteChange(bool enabled) async {
    final config = await load();
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, _configFileName));
    final updated = SyncFolderConfig(
      syncFolderPath: config.syncFolderPath,
      deviceId: config.deviceId,
      autoSyncOnRemoteChange: enabled,
    );
    await updated._save(file);
  }

  /// Returns device ID from config, creating and persisting one if missing.
  static Future<String> getOrCreateDeviceId() async {
    final config = await load();
    return config.deviceId;
  }
}
