import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/auth/auth_controller.dart';
import 'core/config/app_config.dart';
import 'features/attendance/attendance_screen.dart';
import 'features/attendance/child_attendance_screen.dart';
import 'features/attendance/teacher_attendance_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/splash_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/home/home_shell.dart';
import 'features/registrations/child_profile_screen.dart';
import 'features/registrations/registration_list_screen.dart';
import 'features/registrations/registration_wizard_screen.dart';
import 'features/services/service_form_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/sync/conflict_resolution_screen.dart';
import 'features/sync/duplicate_resolution_screen.dart';
import 'features/sync/push_report_screen.dart';
import 'features/sync/sync_center_screen.dart';
import 'features/sync/sync_history_screen.dart';
import 'features/teachers/teacher_form_screen.dart';
import 'features/teachers/teacher_list_screen.dart';

/// Route names used across the app.
class Routes {
  Routes._();

  static const splash = '/';
  static const login = '/login';
  static const home = '/home';
  static const settings = '/settings';
  static const sync = '/sync';
  static const syncHistory = '/sync/history';
  static String pushReport(String batchUuid) => '/sync/report/$batchUuid';
  static String resolveDuplicate(String uuid) => '/sync/duplicate/$uuid';
  static String resolveConflict(String uuid) => '/sync/conflict/$uuid';
  static String dashboard(BmaModule m) => '/dashboard/${m.key}';
  static String registrations(BmaModule m) => '/registrations/${m.key}';
  static String newRegistration(BmaModule m) => '/registrations/${m.key}/new';
  static String profile(String uuid) => '/record/$uuid';
  static String editRegistration(String uuid) => '/record/$uuid/edit';
  static String newService(String parentUuid, String entity) => '/record/$parentUuid/service/$entity/new';
  static String editService(String uuid) => '/service/$uuid';
  static String attendance(BmaModule m) => '/attendance/${m.key}';
  static String teacherAttendance(BmaModule m) => '/attendance/${m.key}/teachers';
  static String childAttendance(String uuid) => '/record/$uuid/attendance';
  static String teachers(BmaModule m) => '/teachers/${m.key}';
  static String newTeacher(BmaModule m) => '/teachers/${m.key}/new';
  static String editTeacher(String uuid) => '/teacher/$uuid';
}

/// Notifies GoRouter when the auth state changes so redirects re-run.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(this.ref) {
    ref.listen<AuthState>(authControllerProvider, (_, _) => notifyListeners());
  }

  final Ref ref;
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final listenable = _AuthListenable(ref);
  ref.onDispose(listenable.dispose);
  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: listenable,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final location = state.matchedLocation;
      if (auth.status == AuthStatus.unknown) {
        return location == Routes.splash ? null : Routes.splash;
      }
      if (auth.status == AuthStatus.signedOut) {
        return location == Routes.login ? null : Routes.login;
      }
      if (location == Routes.splash || location == Routes.login) return Routes.home;
      return null;
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: Routes.home, builder: (_, _) => const HomeShell()),
      GoRoute(path: Routes.settings, builder: (_, _) => const SettingsScreen()),
      GoRoute(path: Routes.sync, builder: (_, _) => const SyncCenterScreen()),
      GoRoute(path: Routes.syncHistory, builder: (_, _) => const SyncHistoryScreen()),
      GoRoute(
        path: '/sync/report/:batchUuid',
        builder: (_, state) => PushReportScreen(batchUuid: state.pathParameters['batchUuid']!),
      ),
      GoRoute(
        path: '/sync/duplicate/:uuid',
        builder: (_, state) => DuplicateResolutionScreen(uuid: state.pathParameters['uuid']!),
      ),
      GoRoute(
        path: '/sync/conflict/:uuid',
        builder: (_, state) => ConflictResolutionScreen(uuid: state.pathParameters['uuid']!),
      ),
      GoRoute(
        path: '/dashboard/:module',
        builder: (_, state) => DashboardScreen(module: _module(state)),
      ),
      GoRoute(
        path: '/registrations/:module',
        builder: (_, state) => RegistrationListScreen(module: _module(state)),
      ),
      GoRoute(
        path: '/registrations/:module/new',
        builder: (_, state) => RegistrationWizardScreen(module: _module(state)),
      ),
      GoRoute(
        path: '/record/:uuid',
        builder: (_, state) => ChildProfileScreen(uuid: state.pathParameters['uuid']!),
      ),
      GoRoute(
        path: '/record/:uuid/edit',
        builder: (_, state) => RegistrationWizardScreen(editUuid: state.pathParameters['uuid']),
      ),
      GoRoute(
        path: '/record/:uuid/attendance',
        builder: (_, state) => ChildAttendanceScreen(uuid: state.pathParameters['uuid']!),
      ),
      GoRoute(
        path: '/record/:parentUuid/service/:entity/new',
        builder: (_, state) => ServiceFormScreen(
          parentUuid: state.pathParameters['parentUuid']!,
          entity: state.pathParameters['entity']!,
        ),
      ),
      GoRoute(
        path: '/service/:uuid',
        builder: (_, state) => ServiceFormScreen(editUuid: state.pathParameters['uuid']),
      ),
      GoRoute(
        path: '/attendance/:module',
        builder: (_, state) => AttendanceScreen(module: _module(state)),
      ),
      GoRoute(
        path: '/attendance/:module/teachers',
        builder: (_, state) => TeacherAttendanceScreen(module: _module(state)),
      ),
      GoRoute(
        path: '/teachers/:module',
        builder: (_, state) => TeacherListScreen(module: _module(state)),
      ),
      GoRoute(
        path: '/teachers/:module/new',
        builder: (_, state) => TeacherFormScreen(module: _module(state)),
      ),
      GoRoute(
        path: '/teacher/:uuid',
        builder: (_, state) => TeacherFormScreen(editUuid: state.pathParameters['uuid']),
      ),
    ],
  );
});

BmaModule _module(GoRouterState state) =>
    BmaModuleKey.fromKey(state.pathParameters['module']) ?? BmaModule.mscc;
