import 'package:flutter/material.dart';

import 'child_profile_view.dart';

/// Route wrapper for `/record/:uuid`.
///
/// The body — summary, information, services and attendance — lives in
/// [ChildProfileView] so the two-pane beneficiaries list can render the same
/// profile inside its detail pane. `embedded: false` is the unchanged screen:
/// its own Scaffold, app bar, overflow menu and tabs.
class ChildProfileScreen extends StatelessWidget {
  const ChildProfileScreen({super.key, required this.uuid});

  final String uuid;

  @override
  Widget build(BuildContext context) => ChildProfileView(uuid: uuid);
}
