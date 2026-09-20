// Two pieces of state the navigation rail needs and nothing else owns.
//
// 1. WHICH PROGRAMME the rail's module-scoped destinations point at. Every
//    `Routes.*` helper takes a [BmaModule], but the module exists in the app
//    only as the `:module` path segment — so on `/sync` or `/settings` there is
//    nothing to read it from. The shell parses the segment out of each router
//    notification and pushes it here; the rail reads it back.
// 2. WHETHER A FORM HAS UNSAVED EDITS. A rail tap is a `push`/`replace`, and
//    neither triggers `PopScope`, so the form screens cannot defend themselves
//    the way they do against the system back gesture. They publish a
//    confirmation message here instead and [goDestination] asks first.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../config/app_config.dart';
import '../forms/schema_form_controller.dart';

/// The programme the rail's module-scoped destinations address.
///
/// Seeded from `profile.enabledModules.first` and moved by the shell whenever
/// the location carries a `:module` segment, or by the rail's module switcher.
/// A choice survives a profile refresh as long as the module is still enabled,
/// which is why it is kept in a field rather than recomputed from the profile.
class CurrentModule extends Notifier<BmaModule> {
  BmaModule? _chosen;

  @override
  BmaModule build() {
    final modules = ref.watch(currentProfileProvider)?.enabledModules ?? const <BmaModule>[];
    final chosen = _chosen;
    if (chosen != null && modules.contains(chosen)) return chosen;
    return modules.isEmpty ? BmaModule.mscc : modules.first;
  }

  // ignore: use_setters_to_change_properties
  void select(BmaModule module) {
    _chosen = module;
    if (state != module) state = module;
  }
}

final currentModuleProvider = NotifierProvider<CurrentModule, BmaModule>(CurrentModule.new);

/// The module a location addresses, or null when the location has no
/// `:module` segment (`/sync`, `/settings`, `/record/<uuid>`, …).
///
/// Only the two shapes the route table actually uses are parsed:
/// `/<screen>/<module>` and `/<screen>/<module>/<rest>`.
BmaModule? moduleOfLocation(String location) {
  const moduleScoped = {'dashboard', 'analytics', 'registrations', 'attendance', 'teachers'};
  final parts = location.split('/').where((s) => s.isNotEmpty).toList();
  if (parts.length < 2 || !moduleScoped.contains(parts.first)) return null;
  return BmaModuleKey.fromKey(parts[1]);
}

/// The confirmation message to show before navigating away from a form with
/// unsaved edits; null when there is nothing to lose.
///
/// Held as the MESSAGE rather than a bool so the guard has something to show
/// and so a screen that wants a different wording does not need a second flag.
final unsavedWorkProvider = StateProvider<String?>((ref) => null);

/// Publishes [message] into [unsavedWorkProvider] the first time a
/// [SchemaFormController]'s values differ from the snapshot taken when the
/// watch started, and clears it again on save or when the form goes away.
///
/// WHY A SNAPSHOT AND NOT A "TOUCHED" FLAG: `SchemaFormController` notifies for
/// validation and for server errors too, and a reveal can re-run validation
/// without the operator typing anything. Comparing against the loaded values
/// means the guard fires for real edits only — and a field typed and then
/// restored stops counting, which is the answer an operator expects.
///
/// WHY THE CLEAR IS DEFERRED: [dispose] runs while the element tree is being
/// finalised, and writing to a provider there can mark the [ProviderScope]
/// dirty during a build. The microtask lands after that frame.
class UnsavedWorkWatch {
  UnsavedWorkWatch({
    required this.container,
    required this.controller,
    required this.message,
  }) : _snapshot = Map<String, dynamic>.from(controller.values) {
    controller.addListener(_check);
  }

  /// Captured rather than reached for through a [BuildContext]: the clear on
  /// [dispose] happens after the element is gone.
  final ProviderContainer container;
  final SchemaFormController controller;
  final String message;

  Map<String, dynamic> _snapshot;
  bool _dirty = false;

  @visibleForTesting
  bool get isDirty => _dirty;

  void _check() {
    if (_dirty || mapEquals(controller.values, _snapshot)) return;
    _dirty = true;
    _write(message);
  }

  /// Called when the edits have been persisted: the form is clean again and the
  /// values it now holds become the new baseline.
  void clear() {
    _snapshot = Map<String, dynamic>.from(controller.values);
    if (!_dirty) return;
    _dirty = false;
    _write(null);
  }

  void dispose() {
    controller.removeListener(_check);
    if (!_dirty) return;
    _dirty = false;
    Future.microtask(() => _write(null));
  }

  void _write(String? value) {
    try {
      container.read(unsavedWorkProvider.notifier).state = value;
    } on StateError {
      // The container was torn down first (app shutdown, or a widget test
      // ending). There is no rail left to guard.
    }
  }
}
