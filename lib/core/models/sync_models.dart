import 'dart:convert';

/// Result of one pushed item as returned by `POST /api/mobile/v1/push/`.
class PushItemResult {
  const PushItemResult({
    required this.clientUuid,
    required this.entity,
    required this.status,
    this.serverId,
    this.parentId,
    this.message = '',
    this.errors = const {},
    this.duplicates = const [],
    this.dataAfter,
    this.createdEntity,
    this.updatedEntity,
    this.key,
  });

  final String clientUuid;
  final String entity;
  final String status;
  final int? serverId;
  final int? parentId;
  final String message;
  final Map<String, dynamic> errors;
  final List<Map<String, dynamic>> duplicates;
  final Map<String, dynamic>? dataAfter;

  /// Set when the server created a different entity than the one pushed
  /// (e.g. a `mscc.new_round` item creates a `mscc.registration`).
  final String? createdEntity;

  /// Set when the pushed item updated a different (parent) entity, e.g. a
  /// `clm.bridging_assessment` item updates its `clm.bridging` registration.
  final String? updatedEntity;
  final String? key;

  bool get isSuccess =>
      status == 'created' || status == 'updated' || status == 'merged' || status == 'linked' || status == 'deleted';

  static PushItemResult fromJson(Map<String, dynamic> json) => PushItemResult(
        clientUuid: (json['client_uuid'] ?? '').toString(),
        entity: (json['entity'] ?? '').toString(),
        status: (json['status'] ?? 'error').toString(),
        serverId: (json['server_id'] as num?)?.toInt(),
        parentId: (json['parent_id'] as num?)?.toInt(),
        message: (json['message'] ?? '').toString(),
        errors: json['errors'] is Map ? Map<String, dynamic>.from(json['errors'] as Map) : const {},
        duplicates: ((json['duplicates'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
        dataAfter: json['data_after'] is Map ? Map<String, dynamic>.from(json['data_after'] as Map) : null,
        createdEntity: json['created_entity']?.toString(),
        updatedEntity: json['updated_entity']?.toString(),
        key: json['key']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'client_uuid': clientUuid,
        'entity': entity,
        'status': status,
        'server_id': serverId,
        'parent_id': parentId,
        'message': message,
        'errors': errors,
        'duplicates': duplicates,
        if (dataAfter != null) 'data_after': dataAfter,
        if (createdEntity != null) 'created_entity': createdEntity,
        if (updatedEntity != null) 'updated_entity': updatedEntity,
        if (key != null) 'key': key,
      };
}

/// Report of a whole push batch.
class PushReport {
  const PushReport({
    required this.batchId,
    required this.batchUuid,
    required this.status,
    required this.summary,
    required this.results,
    this.receivedAt,
  });

  final int? batchId;
  final String batchUuid;
  final String status;
  final Map<String, int> summary;
  final List<PushItemResult> results;
  final String? receivedAt;

  int count(String status) => summary[status] ?? 0;

  static PushReport fromJson(Map<String, dynamic> json) => PushReport(
        batchId: (json['batch_id'] as num?)?.toInt(),
        batchUuid: (json['batch_uuid'] ?? '').toString(),
        status: (json['status'] ?? '').toString(),
        summary: (json['summary'] is Map)
            ? (json['summary'] as Map).map((k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0))
            : const {},
        results: ((json['results'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => PushItemResult.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        receivedAt: json['received_at']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'batch_id': batchId,
        'batch_uuid': batchUuid,
        'status': status,
        'summary': summary,
        'results': results.map((r) => r.toJson()).toList(),
        'received_at': receivedAt,
      };
}

/// Local history row for a batch (`sync_batches` table).
class SyncBatch {
  const SyncBatch({
    required this.uuid,
    required this.startedAt,
    required this.status,
    this.serverBatchId,
    this.finishedAt,
    this.summary = const {},
    this.itemCount = 0,
    this.report,
    this.error,
  });

  final String uuid;
  final int? serverBatchId;
  final String startedAt;
  final String? finishedAt;

  /// pushing | completed | failed
  final String status;
  final Map<String, int> summary;
  final int itemCount;
  final PushReport? report;
  final String? error;

  Map<String, Object?> toRow() => {
        'uuid': uuid,
        'server_batch_id': serverBatchId,
        'started_at': startedAt,
        'finished_at': finishedAt,
        'status': status,
        'summary': jsonEncode(summary),
        'item_count': itemCount,
        'report': report == null ? null : jsonEncode(report!.toJson()),
        'error': error,
      };

  static SyncBatch fromRow(Map<String, Object?> row) => SyncBatch(
        uuid: row['uuid'] as String,
        serverBatchId: row['server_batch_id'] as int?,
        startedAt: row['started_at'] as String,
        finishedAt: row['finished_at'] as String?,
        status: row['status'] as String,
        summary: row['summary'] == null
            ? const {}
            : (jsonDecode(row['summary'] as String) as Map)
                .map((k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0)),
        itemCount: (row['item_count'] as int?) ?? 0,
        report: row['report'] == null
            ? null
            : PushReport.fromJson(Map<String, dynamic>.from(jsonDecode(row['report'] as String) as Map)),
        error: row['error'] as String?,
      );
}

/// One change returned by `GET /api/mobile/v1/pull/`.
class PullChange {
  const PullChange({
    required this.entity,
    required this.data,
    this.serverId,
    this.parentId,
    this.modified,
    this.deleted = false,
    this.key,
  });

  final String entity;
  final int? serverId;
  final int? parentId;
  final String? modified;
  final bool deleted;
  final String? key;
  final Map<String, dynamic> data;

  static PullChange fromJson(Map<String, dynamic> json) => PullChange(
        entity: (json['entity'] ?? '').toString(),
        serverId: (json['server_id'] as num?)?.toInt(),
        parentId: (json['parent_id'] as num?)?.toInt(),
        modified: json['modified']?.toString(),
        deleted: json['deleted'] == true,
        key: json['key']?.toString(),
        data: json['data'] is Map ? Map<String, dynamic>.from(json['data'] as Map) : const {},
      );
}
