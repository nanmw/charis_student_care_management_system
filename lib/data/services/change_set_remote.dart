/// Parsed row from a remote or imported change-set (before inserting into the local DB).
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

/// One change-set row as stored in the remote database, with its sequence cursor.
class RemoteChangeSet {
  const RemoteChangeSet({
    required this.seq,
    required this.record,
  });

  final int seq;
  final ChangeSetRecord record;
}

/// Push and pull of the shared change-set log.
///
/// Implementations open whatever connection they need. [close] releases it.
abstract class ChangeSetRemote {
  Future<void> push(List<ChangeSetRecord> rows);

  Future<List<RemoteChangeSet>> pullAfter(int afterSeq, {int limit = 200});

  Future<void> close();
}
