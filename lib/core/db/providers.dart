import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/entity_record.dart';
import '../models/form_schema.dart';
import 'entity_dao.dart';
import 'reference_dao.dart';

/// Incremented after every local write or sync so list screens reload.
final dataVersionProvider = StateProvider<int>((ref) => 0);

/// Works from providers ([Ref]) and widgets ([WidgetRef]).
void bumpDataVersion(Object ref) {
  if (ref is WidgetRef) {
    ref.read(dataVersionProvider.notifier).state++;
  } else if (ref is Ref) {
    ref.read(dataVersionProvider.notifier).state++;
  }
}

/// All form schemas downloaded at bootstrap.
final schemasProvider = FutureProvider<Map<String, EntitySchema>>((ref) async {
  ref.watch(dataVersionProvider);
  return ref.watch(referenceDaoProvider).allSchemas();
});

final schemaProvider = FutureProvider.family<EntitySchema?, String>((ref, entity) async {
  final schemas = await ref.watch(schemasProvider.future);
  return schemas[entity];
});

final recordProvider = FutureProvider.family<EntityRecord?, String>((ref, uuid) async {
  ref.watch(dataVersionProvider);
  return ref.watch(entityDaoProvider).byUuid(uuid);
});

final childRecordsProvider = FutureProvider.family<List<EntityRecord>, String>((ref, uuid) async {
  ref.watch(dataVersionProvider);
  final dao = ref.watch(entityDaoProvider);
  final parent = await dao.byUuid(uuid);
  if (parent == null) return const [];
  return dao.childrenOf(parent);
});

final bootstrapReadyProvider = FutureProvider<bool>((ref) async {
  ref.watch(dataVersionProvider);
  return ref.watch(referenceDaoProvider).hasBootstrap;
});
