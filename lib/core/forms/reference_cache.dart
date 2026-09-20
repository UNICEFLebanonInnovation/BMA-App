import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/reference_dao.dart';
import '../models/form_schema.dart';
import '../models/reference_item.dart';
import 'schema_form_controller.dart';

/// In-memory cache of reference lists used to turn ids into labels quickly
/// (lists, review screens, reveal rules).
class ReferenceCache {
  ReferenceCache(this._dao);

  final ReferenceDao _dao;
  final Map<String, Map<int, ReferenceItem>> _maps = {};
  final Map<String, List<ChoiceRow>> _choices = {};

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

  Future<List<ChoiceRow>> choices(String key) async =>
      _choices[key] ??= await _dao.choices(key);

  /// Ids of a reference list, as strings, or null when the list is not in
  /// memory. Null means "cannot tell" to the validator, never "invalid".
  Set<String>? cachedRefValues(String kind) {
    final map = _maps[kind];
    return map == null ? null : {for (final id in map.keys) '$id'};
  }

  /// Values of a shared choice list, or null when it has not been read yet.
  Set<String>? cachedChoiceValues(String key) {
    final rows = _choices[key];
    return rows == null ? null : {for (final r in rows) r.value};
  }

  /// Warm everything a schema's validator needs to check membership.
  ///
  /// Called before a form opens so the answer is available synchronously
  /// during validation; anything still missing is simply not checked.
  Future<void> warmFor(EntitySchema schema) async {
    for (final field in [...schema.fields, ...schema.rowFields]) {
      if (field.isReference && field.ref != null && field.ref != 'parent') {
        await ensure(field.ref!);
      }
      if (field.choicesRef != null) {
        await choices(field.choicesRef!);
      }
    }
  }

  Future<ReferenceItem?> item(String kind, int? id) async {
    if (id == null) return null;
    return (await ensure(kind))[id];
  }

  Future<String> label(String kind, Object? id, String languageCode) async {
    final parsed = id is int ? id : int.tryParse(id?.toString() ?? '');
    final item = await this.item(kind, parsed);
    return item?.labelFor(languageCode) ?? (id?.toString() ?? '');
  }

  void invalidate() {
    _maps.clear();
    _choices.clear();
  }
}

/// The validator's view of this cache: inline choices are handled by the
/// controller, so this answers only for `choices_ref` and reference lists.
AllowedValuesResolver allowedValuesFrom(ReferenceCache cache) => (field) {
      if (field.choicesRef != null) return cache.cachedChoiceValues(field.choicesRef!);
      // `parent` is the record this one hangs off, not a list to pick from.
      if (field.isReference && field.ref != null && field.ref != 'parent') {
        return cache.cachedRefValues(field.ref!);
      }
      return null;
    };

final referenceCacheProvider = Provider<ReferenceCache>((ref) => ReferenceCache(ref.watch(referenceDaoProvider)));

/// Items of one reference kind (re-evaluated when invalidated after a sync).
final referenceListProvider = FutureProvider.family<List<ReferenceItem>, String>((ref, kind) async {
  return ref.watch(referenceCacheProvider).list(kind);
});
