import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/reference_dao.dart';
import '../models/reference_item.dart';

/// In-memory cache of reference lists used to turn ids into labels quickly
/// (lists, review screens, reveal rules).
class ReferenceCache {
  ReferenceCache(this._dao);

  final ReferenceDao _dao;
  final Map<String, Map<int, ReferenceItem>> _maps = {};

  Future<Map<int, ReferenceItem>> ensure(String kind) async {
    final cached = _maps[kind];
    if (cached != null) return cached;
    final map = await _dao.mapOf(kind);
    _maps[kind] = map;
    return map;
  }

  Future<List<ReferenceItem>> list(String kind) async => (await ensure(kind)).values.toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  ReferenceItem? cached(String kind, int? id) => id == null ? null : _maps[kind]?[id];

  Future<ReferenceItem?> item(String kind, int? id) async {
    if (id == null) return null;
    return (await ensure(kind))[id];
  }

  Future<String> label(String kind, Object? id, String languageCode) async {
    final parsed = id is int ? id : int.tryParse(id?.toString() ?? '');
    final item = await this.item(kind, parsed);
    return item?.labelFor(languageCode) ?? (id?.toString() ?? '');
  }

  void invalidate() => _maps.clear();
}

final referenceCacheProvider = Provider<ReferenceCache>((ref) => ReferenceCache(ref.watch(referenceDaoProvider)));

/// Items of one reference kind (re-evaluated when invalidated after a sync).
final referenceListProvider = FutureProvider.family<List<ReferenceItem>, String>((ref, kind) async {
  return ref.watch(referenceCacheProvider).list(kind);
});
