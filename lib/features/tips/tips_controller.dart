import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/config/app_config.dart';

/// Which accounts on this device have seen the getting-started wizard and
/// which contextual tips they closed. Device-local, never synced.
class TipsState {
  const TipsState({this.seen = const {}, this.dismissed = const {}});

  /// `<UserProfile.id>:<AppConfig.tipsVersion>` per account that finished or
  /// skipped the wizard.
  final Set<String> seen;

  /// `<UserProfile.id>:<tipId>` per contextual TipCard closed with "Got it".
  final Set<String> dismissed;

  static String seenKey(int userId) => '$userId:${AppConfig.tipsVersion}';

  bool hasSeen(int? userId) => userId != null && seen.contains(seenKey(userId));

  bool isDismissed(int? userId, String tipId) => userId != null && dismissed.contains('$userId:$tipId');

  TipsState copyWith({Set<String>? seen, Set<String>? dismissed}) =>
      TipsState(seen: seen ?? this.seen, dismissed: dismissed ?? this.dismissed);
}

/// Same shape as SettingsController: loaded before runApp, prefs nullable so
/// tests get an in-memory instance.
class TipsController extends Notifier<TipsState> {
  TipsController(this._initial, this._prefs);

  static const keySeen = 'tips_seen';
  static const keyDismissed = 'tips_dismissed';

  final TipsState _initial;
  final SharedPreferences? _prefs;

  static Future<TipsController> load() async {
    final prefs = await SharedPreferences.getInstance();
    return TipsController(
      TipsState(
        seen: (prefs.getStringList(keySeen) ?? const []).toSet(),
        dismissed: (prefs.getStringList(keyDismissed) ?? const []).toSet(),
      ),
      prefs,
    );
  }

  @override
  TipsState build() => _initial;

  /// State first (synchronously) so the very next redirect already sees it.
  Future<void> markSeen(int userId) async {
    state = state.copyWith(seen: {...state.seen, TipsState.seenKey(userId)});
    await _prefs?.setStringList(keySeen, state.seen.toList()..sort());
  }

  Future<void> dismissTip(int userId, String tipId) async {
    state = state.copyWith(dismissed: {...state.dismissed, '$userId:$tipId'});
    await _prefs?.setStringList(keyDismissed, state.dismissed.toList()..sort());
  }

  /// Brings back this user's contextual tips. Deliberately never touches `seen`.
  Future<void> restoreTips(int userId) async {
    state = state.copyWith(dismissed: state.dismissed.where((e) => !e.startsWith('$userId:')).toSet());
    await _prefs?.setStringList(keyDismissed, state.dismissed.toList()..sort());
  }
}

/// Working in-memory default (NOT throw UnimplementedError): existing tests and
/// the screenshot harness keep working without an override; main() overrides
/// it with the loaded instance.
final tipsControllerProvider =
    NotifierProvider<TipsController, TipsState>(() => TipsController(const TipsState(), null));

/// True while the signed-in account still has to see the wizard.
final tipsPendingProvider = Provider<bool>((ref) {
  final auth = ref.watch(authControllerProvider);
  // isSignedIn implies profile != null.
  if (!auth.isSignedIn) return false;
  return !ref.watch(tipsControllerProvider).hasSeen(auth.profile!.id);
});
