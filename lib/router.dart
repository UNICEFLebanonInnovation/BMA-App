import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/auth/auth_controller.dart';
import 'core/config/app_config.dart';
import 'core/config/settings_controller.dart';
import 'features/attendance/attendance_screen.dart';
import 'features/attendance/child_attendance_screen.dart';
import 'features/attendance/teacher_attendance_screen.dart';
import 'features/analytics/alp/alp_attendance_dashboard_screen.dart';
import 'features/analytics/alp/alp_registration_insights_screen.dart';
import 'features/analytics/alp/alp_school_dashboard_screen.dart';
import 'features/analytics/alp/alp_teacher_dashboard_screen.dart';
import 'features/analytics/analytics_hub_screen.dart';
import 'features/analytics/nfe/nfe_advanced_analytics_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/splash_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/home/home_shell.dart';
import 'features/registrations/child_profile_screen.dart';
import 'features/registrations/registration_list_screen.dart';
import 'features/registrations/registration_wizard_screen.dart';
import 'features/services/service_form_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/profiles/facility_profile_screen.dart';
import 'features/setup/server_setup_screen.dart';
import 'features/sync/conflict_resolution_screen.dart';
import 'features/sync/duplicate_resolution_screen.dart';
import 'features/sync/push_report_screen.dart';
import 'features/sync/sync_center_screen.dart';
import 'features/sync/sync_history_screen.dart';
import 'features/teachers/teacher_form_screen.dart';
import 'features/teachers/teacher_list_screen.dart';
import 'features/tips/tips_controller.dart';
import 'features/tips/tips_wizard_screen.dart';

/// Route names used across the app.
class Routes {
  Routes._();

  static const splash = '/';
  static const login = '/login';
  static const setup = '/setup';
  static const home = '/home';
  static const settings = '/settings';
  static const sync = '/sync';
  static const tips = '/tips';
  static const centerProfile = '/profile/center';
  static const schoolProfile = '/profile/school';
  /// Form of an entity that has no parent record (the ALP school profile).
  static String standaloneForm(String entity) => '/form/$entity';
  static const syncHistory = '/sync/history';
  static String pushReport(String batchUuid) => '/sync/report/$batchUuid';
  static String resolveDuplicate(String uuid) => '/sync/duplicate/$uuid';
  static String resolveConflict(String uuid) => '/sync/conflict/$uuid';
  static String dashboard(BmaModule m) => '/dashboard/${m.key}';

  /// The hub listing a programme's analytics dashboards, and the dashboards
  /// themselves. They live under the same `/analytics/<module>` prefix so the
  /// rail keeps the Analytics destination highlighted while one is open and
  /// `moduleOfLocation` can read the programme back from any of them.
  static String analytics(BmaModule m) => '/analytics/${m.key}';
  static const nfeAdvancedAnalytics = '/analytics/mscc/advanced';
  static const alpRegistrationInsights = '/analytics/alp/registration';
  static const alpTeacherDashboard = '/analytics/alp/teachers';
  static const alpAttendanceDashboard = '/analytics/alp/attendance';
  static const alpSchoolDashboard = '/analytics/alp/schools';
  static String registrations(BmaModule m) => '/registrations/${m.key}';

  /// The beneficiaries list with one child selected. The selection is a query
  /// parameter on the SAME route, so `replace` keeps the page (and its State)
  /// and the link is shareable. `matchedLocation` ignores query strings, so the
  /// redirect at the top of the router is unaffected.
  static String registrationsSelected(BmaModule m, String uuid) => '/registrations/${m.key}?sel=$uuid';
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
        // A device where nobody confirmed a server address yet lands on the
        // first-run setup page instead of the sign-in form.
        if (!ref.read(settingsControllerProvider).serverConfigured) {
          return location == Routes.setup ? null : Routes.setup;
        }
        return location == Routes.login ? null : Routes.login;
      }
      // Signed in from here on. The wizard route itself never redirects (seen or not): loop-free
      // and re-openable from Home/Settings. A first-run account is gated to /tips from anywhere.
      if (location == Routes.tips) return null;
      if (ref.read(tipsPendingProvider)) return Routes.tips;
      if (location == Routes.splash || location == Routes.login || location == Routes.setup) {
        return Routes.home;
      }
      return null;
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: Routes.setup, builder: (_, _) => const ServerSetupScreen()),
      GoRoute(path: Routes.home, builder: (_, _) => const HomeShell()),
      GoRoute(path: Routes.settings, builder: (_, _) => const SettingsScreen()),
      GoRoute(path: Routes.tips, builder: (_, _) => const TipsWizardScreen()),
      GoRoute(path: Routes.centerProfile, builder: (_, _) => const CenterProfileScreen()),
      GoRoute(path: Routes.schoolProfile, builder: (_, _) => const SchoolProfileScreen()),
      GoRoute(
        path: '/form/:entity',
        builder: (_, state) => ServiceFormScreen(entity: state.pathParameters['entity']),
      ),
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
      // The five dashboards are registered BEFORE the hub's `/analytics/:module`
      // so a fixed path is never read as a module segment.
      GoRoute(path: Routes.nfeAdvancedAnalytics, builder: (_, _) => const NfeAdvancedAnalyticsScreen()),
      GoRoute(path: Routes.alpRegistrationInsights, builder: (_, _) => const AlpRegistrationInsightsScreen()),
      GoRoute(path: Routes.alpTeacherDashboard, builder: (_, _) => const AlpTeacherDashboardScreen()),
      GoRoute(path: Routes.alpAttendanceDashboard, builder: (_, _) => const AlpAttendanceDashboardScreen()),
      GoRoute(path: Routes.alpSchoolDashboard, builder: (_, _) => const AlpSchoolDashboardScreen()),
      GoRoute(
        path: '/analytics/:module',
        builder: (_, state) => AnalyticsHubScreen(module: _module(state)),
      ),
      GoRoute(
        path: '/registrations/:module',
        builder: (_, state) => RegistrationListScreen(
          module: _module(state),
          selectedUuid: state.uri.queryParameters['sel'],
        ),
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
