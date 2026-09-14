import 'dart:convert';

/// Local synchronisation state of a record (see docs/mobile_sync_protocol.md §5).
enum SyncState {
  synced,
  pending,
  pushing,
  duplicate,
  conflict,
  error,
  discarded;

  static SyncState fromKey(String? key) => SyncState.values.firstWhere(
        (s) => s.name == key,
        orElse: () => SyncState.synced,
      );

  bool get needsAttention =>
      this == SyncState.duplicate ||
      this == SyncState.conflict ||
      this == SyncState.error;

  bool get isOutbound =>
      this == SyncState.pending ||
      this == SyncState.duplicate ||
      this == SyncState.conflict ||
      this == SyncState.error;
}

/// One row of the generic `records` table: any entity the server registry
/// knows (registration, service, teacher, attendance day …) stored as a JSON
/// document plus indexed columns for search and sync bookkeeping.
class EntityRecord {
  EntityRecord({
    required this.uuid,
    required this.entity,
    required this.module,
    required this.data,
    this.serverId,
    this.parentUuid,
    this.parentServerId,
    this.naturalKey,
    this.label = '',
    this.search = '',
    this.syncState = SyncState.synced,
    this.op,
    this.serverModified,
    this.baseModified,
    this.clientModified,
    this.createdAt,
    this.deleted = false,
    this.lastError,
    this.duplicates = const [],
    this.conflictData,
    this.resolution,
    this.serverMessage,
  });

  final String uuid;
  final String entity;
  final String module;
  final Map<String, dynamic> data;
  final int? serverId;
  final String? parentUuid;
  final int? parentServerId;
  final String? naturalKey;
  final String label;
  final String search;
  final SyncState syncState;

  /// Pending operation to push: create | update | delete | upsert.
  final String? op;
  final String? serverModified;
  final String? baseModified;
  final String? clientModified;
  final String? createdAt;
  final bool deleted;
  final Map<String, dynamic>? lastError;
  final List<Map<String, dynamic>> duplicates;
  final Map<String, dynamic>? conflictData;
  final Map<String, dynamic>? resolution;
  final String? serverMessage;

  bool get isLocalOnly => serverId == null;

  EntityRecord copyWith({
    Map<String, dynamic>? data,
    int? serverId,
    String? parentUuid,
    int? parentServerId,
    String? naturalKey,
    String? label,
    String? search,
    SyncState? syncState,
    String? op,
    bool clearOp = false,
    String? serverModified,
    String? baseModified,
    String? clientModified,
    String? createdAt,
    bool? deleted,
    Map<String, dynamic>? lastError,
    bool clearError = false,
    List<Map<String, dynamic>>? duplicates,
    Map<String, dynamic>? conflictData,
    bool clearConflict = false,
    Map<String, dynamic>? resolution,
    bool clearResolution = false,
    String? serverMessage,
  }) {
    return EntityRecord(
      uuid: uuid,
      entity: entity,
      module: module,
      data: data ?? this.data,
      serverId: serverId ?? this.serverId,
      parentUuid: parentUuid ?? this.parentUuid,
      parentServerId: parentServerId ?? this.parentServerId,
      naturalKey: naturalKey ?? this.naturalKey,
      label: label ?? this.label,
      search: search ?? this.search,
      syncState: syncState ?? this.syncState,
      op: clearOp ? null : (op ?? this.op),
      serverModified: serverModified ?? this.serverModified,
      baseModified: baseModified ?? this.baseModified,
      clientModified: clientModified ?? this.clientModified,
      createdAt: createdAt ?? this.createdAt,
      deleted: deleted ?? this.deleted,
      lastError: clearError ? null : (lastError ?? this.lastError),
      duplicates: duplicates ?? this.duplicates,
      conflictData: clearConflict ? null : (conflictData ?? this.conflictData),
      resolution: clearResolution ? null : (resolution ?? this.resolution),
      serverMessage: serverMessage ?? this.serverMessage,
    );
  }

  Map<String, Object?> toRow() => {
        'uuid': uuid,
        'entity': entity,
        'module': module,
        'server_id': serverId,
        'parent_uuid': parentUuid,
        'parent_server_id': parentServerId,
        'natural_key': naturalKey,
        'label': label,
        'search': search,
        'data': jsonEncode(data),
        'sync_state': syncState.name,
        'op': op,
        'server_modified': serverModified,
        'base_modified': baseModified,
        'client_modified': clientModified,
        'created_at': createdAt,
        'deleted': deleted ? 1 : 0,
        'last_error': lastError == null ? null : jsonEncode(lastError),
        'duplicates': jsonEncode(duplicates),
        'conflict_data': conflictData == null ? null : jsonEncode(conflictData),
        'resolution': resolution == null ? null : jsonEncode(resolution),
        'server_message': serverMessage,
      };

  static EntityRecord fromRow(Map<String, Object?> row) {
    Map<String, dynamic>? decodeMap(Object? value) {
      if (value == null) return null;
      final decoded = jsonDecode(value as String);
      return decoded is Map<String, dynamic> ? decoded : null;
    }

    List<Map<String, dynamic>> decodeList(Object? value) {
      if (value == null) return const [];
      final decoded = jsonDecode(value as String);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return const [];
    }

    return EntityRecord(
      uuid: row['uuid'] as String,
      entity: row['entity'] as String,
      module: row['module'] as String,
      data: decodeMap(row['data']) ?? <String, dynamic>{},
      serverId: row['server_id'] as int?,
      parentUuid: row['parent_uuid'] as String?,
      parentServerId: row['parent_server_id'] as int?,
      naturalKey: row['natural_key'] as String?,
      label: (row['label'] as String?) ?? '',
      search: (row['search'] as String?) ?? '',
      syncState: SyncState.fromKey(row['sync_state'] as String?),
      op: row['op'] as String?,
      serverModified: row['server_modified'] as String?,
      baseModified: row['base_modified'] as String?,
      clientModified: row['client_modified'] as String?,
      createdAt: row['created_at'] as String?,
      deleted: (row['deleted'] as int? ?? 0) == 1,
      lastError: decodeMap(row['last_error']),
      duplicates: decodeList(row['duplicates']),
      conflictData: decodeMap(row['conflict_data']),
      resolution: decodeMap(row['resolution']),
      serverMessage: row['server_message'] as String?,
    );
  }
}
