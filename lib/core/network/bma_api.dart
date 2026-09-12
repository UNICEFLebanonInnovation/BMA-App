import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../models/sync_models.dart';
import '../models/user_profile.dart';
import 'api_client.dart';

/// Typed access to the endpoints of `student_registration.mobile_api`.
class BmaApi {
  BmaApi(this._client);

  final ApiClient _client;

  set token(String? value) => _client.token = value;

  Future<({String token, UserProfile profile, String serverTime})> login({
    required String username,
    required String password,
    required String deviceId,
    String? deviceName,
  }) async {
    final json = await _client.post('/auth/login/', {
      'username': username,
      'password': password,
      'device_id': deviceId,
      'device_name': deviceName ?? '',
      'app_version': AppConfig.appVersion,
    }, auth: false);
    return (
      token: json['token'] as String,
      profile: UserProfile.fromJson(Map<String, dynamic>.from(json['user'] as Map)),
      serverTime: (json['server_time'] ?? '').toString(),
    );
  }

  Future<void> logout() => _client.post('/auth/logout/', const {});

  Future<UserProfile> me() async {
    final json = await _client.get('/me/');
    return UserProfile.fromJson(Map<String, dynamic>.from(json['user'] as Map));
  }

  Future<Map<String, dynamic>> bootstrap({required String deviceId}) =>
      _client.get('/bootstrap/', query: {'device_id': deviceId, 'app_version': AppConfig.appVersion});

  Future<({List<PullChange> changes, String serverTime, String? nextCursor, bool hasMore})> pull({
    String? since,
    String? cursor,
    int limit = AppConfig.pullPageSize,
    List<String>? entities,
    required String deviceId,
  }) async {
    final json = await _client.get('/pull/', query: {
      'since': ?since,
      'cursor': ?cursor,
      'limit': limit,
      if (entities != null && entities.isNotEmpty) 'entities': entities.join(','),
      'device_id': deviceId,
    });
    final changes = ((json['changes'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => PullChange.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return (
      changes: changes,
      serverTime: (json['server_time'] ?? '').toString(),
      nextCursor: json['next_cursor']?.toString(),
      hasMore: json['has_more'] == true,
    );
  }

  Future<PushReport> push({
    required String batchUuid,
    required String deviceId,
    required List<Map<String, dynamic>> items,
  }) async {
    final json = await _client.post('/push/', {
      'batch_uuid': batchUuid,
      'device_id': deviceId,
      'app_version': AppConfig.appVersion,
      'items': items,
    });
    return PushReport.fromJson(json);
  }

  Future<List<Map<String, dynamic>>> history() async {
    final json = await _client.get('/push/history/');
    return ((json['batches'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<PushReport> batch(int batchId) async => PushReport.fromJson(await _client.get('/push/$batchId/'));

  Future<List<Map<String, dynamic>>> duplicateCheck(String entity, Map<String, dynamic> data) async {
    final json = await _client.post('/duplicates/check/', {'entity': entity, 'data': data});
    return ((json['result'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
}

final bmaApiProvider = Provider<BmaApi>((ref) => BmaApi(ref.watch(apiClientProvider)));
