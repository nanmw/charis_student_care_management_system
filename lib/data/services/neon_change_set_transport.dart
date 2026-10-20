import 'package:postgres/postgres.dart';

import 'package:charis_student_care/data/services/change_set_remote.dart';

/// Host, database, and credentials parsed from a Neon connection string.
class NeonEndpoint {
  const NeonEndpoint({
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.password,
  });

  final String host;
  final int port;
  final String database;
  final String username;
  final String password;
}

/// Parses a `postgres://` or `postgresql://` connection string.
///
/// Extra query parameters (such as `sslmode` or `channel_binding`) are ignored.
/// The sync connection always uses SSL.
NeonEndpoint parseNeonConnectionString(String raw) {
  final trimmed = raw.trim();
  final uri = Uri.parse(trimmed);
  if (uri.scheme != 'postgres' && uri.scheme != 'postgresql') {
    throw const FormatException(
      'Connection string must start with postgresql://',
    );
  }
  if (uri.host.isEmpty) {
    throw const FormatException('Connection string is missing a host');
  }

  final params = uri.queryParameters;
  final userInfo = uri.userInfo;
  final username = params['user'] ??
      params['username'] ??
      (userInfo.isEmpty ? null : _userInfoName(userInfo));
  final password = params['password'] ??
      (userInfo.isEmpty ? null : _userInfoPassword(userInfo));
  if (username == null || username.isEmpty || password == null) {
    throw const FormatException(
      'Connection string is missing a username and password',
    );
  }

  final database = params['database'] ??
      (uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '');
  if (database.isEmpty) {
    throw const FormatException('Connection string is missing a database name');
  }

  final portParam = int.tryParse(params['port'] ?? '');
  final port = portParam ?? (uri.hasPort ? uri.port : 5432);

  return NeonEndpoint(
    host: uri.host,
    port: port,
    database: database,
    username: username,
    password: password,
  );
}

String _userInfoName(String userInfo) {
  final splitAt = userInfo.indexOf(':');
  final raw = splitAt == -1 ? userInfo : userInfo.substring(0, splitAt);
  return Uri.decodeComponent(raw);
}

String? _userInfoPassword(String userInfo) {
  final splitAt = userInfo.indexOf(':');
  if (splitAt == -1) return null;
  return Uri.decodeComponent(userInfo.substring(splitAt + 1));
}

/// Short-lived Postgres connection to the shared Neon `change_sets` table.
class NeonChangeSetTransport implements ChangeSetRemote {
  NeonChangeSetTransport(this.connectionString);

  final String connectionString;

  Connection? _connection;

  static final Sql _insert = Sql.named('''
INSERT INTO change_sets (
  id, table_name, record_id, operation, payload,
  occurred_at, user_id, version, device_id
) VALUES (
  @id, @table_name, @record_id, @operation, @payload,
  @occurred_at, @user_id, @version, @device_id
)
ON CONFLICT (id) DO NOTHING
''');

  static final Sql _pull = Sql.named('''
SELECT seq, id, table_name, record_id, operation, payload,
       occurred_at, user_id, version, device_id
FROM change_sets
WHERE seq > @after
ORDER BY seq
LIMIT @lim
''');

  @override
  Future<void> push(List<ChangeSetRecord> rows) async {
    if (rows.isEmpty) return;
    final conn = await _open();
    await conn.runTx((session) async {
      for (final row in rows) {
        await session.execute(
          _insert,
          parameters: {
            'id': TypedValue(Type.text, row.id),
            'table_name': TypedValue(Type.text, row.table),
            'record_id': TypedValue(Type.text, row.recordId),
            'operation': TypedValue(Type.text, row.operation),
            'payload': TypedValue(Type.text, row.payload),
            'occurred_at': TypedValue(Type.timestampTz, row.timestamp.toUtc()),
            'user_id': TypedValue(Type.text, row.userId),
            'version': TypedValue(Type.integer, row.version),
            'device_id': TypedValue(Type.text, row.deviceId),
          },
        );
      }
    });
  }

  @override
  Future<List<RemoteChangeSet>> pullAfter(
    int afterSeq, {
    int limit = 200,
  }) async {
    final conn = await _open();
    final result = await conn.execute(
      _pull,
      parameters: {
        'after': TypedValue(Type.bigInteger, afterSeq),
        'lim': TypedValue(Type.integer, limit),
      },
    );
    return result.map(_rowToRemote).toList();
  }

  @override
  Future<void> close() async {
    final conn = _connection;
    _connection = null;
    if (conn != null) {
      await conn.close();
    }
  }

  Future<Connection> _open() async {
    final existing = _connection;
    if (existing != null && existing.isOpen) return existing;
    final endpoint = parseNeonConnectionString(connectionString);
    // Uses the vendored postgres package so the TLS handshake includes this
    // hostname. Neon routes the connection by that name.
    final opened = await Connection.open(
      Endpoint(
        host: endpoint.host,
        port: endpoint.port,
        database: endpoint.database,
        username: endpoint.username,
        password: endpoint.password,
      ),
      settings: const ConnectionSettings(
        sslMode: SslMode.require,
        connectTimeout: Duration(seconds: 20),
        queryTimeout: Duration(seconds: 30),
        // Default extended protocol. This driver sends each parameterized
        // statement as one unnamed parse/bind/execute, which Neon’s pooler
        // accepts. Simple mode cannot send parameters.
      ),
    );
    _connection = opened;
    return opened;
  }

  RemoteChangeSet _rowToRemote(ResultRow row) {
    final map = row.toColumnMap();
    final occurred = map['occurred_at'];
    final timestamp = occurred is DateTime
        ? occurred.toUtc()
        : DateTime.parse(occurred.toString()).toUtc();
    return RemoteChangeSet(
      seq: _asInt(map['seq']),
      record: ChangeSetRecord(
        id: map['id'] as String,
        table: map['table_name'] as String,
        recordId: map['record_id'] as String,
        operation: map['operation'] as String,
        payload: map['payload'] as String,
        timestamp: timestamp,
        userId: map['user_id'] as String,
        version: _asInt(map['version']),
        deviceId: map['device_id'] as String,
      ),
    );
  }

  int _asInt(Object? value) {
    if (value is int) return value;
    if (value is BigInt) return value.toInt();
    if (value is num) return value.toInt();
    throw FormatException('Expected an integer from Neon, got $value');
  }
}
