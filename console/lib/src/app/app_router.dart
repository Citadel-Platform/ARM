import 'package:arm_console/src/app/console_shell.dart';
import 'package:arm_console/src/features/auth/auth_controller.dart';
import 'package:arm_console/src/features/auth/auth_pages.dart';
import 'package:arm_console/src/features/auth/domain/auth_models.dart';
import 'package:arm_console/src/features/cases/case_detail_page.dart';
import 'package:arm_console/src/features/console_pages.dart';
import 'package:arm_console/src/features/explorer/cases_page.dart';
import 'package:arm_console/src/features/explorer/issues_page.dart';
import 'package:arm_console/src/features/overview/overview_page.dart';
import 'package:arm_console/src/features/projects/project_controller.dart';
import 'package:arm_console/src/features/projects/projects_page.dart';
import 'package:arm_console/src/features/reports/reports_page.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

enum ConsoleDestination {
  overview(
    label: 'Overview',
    path: '/overview',
    icon: Icons.space_dashboard_outlined,
    selectedIcon: Icons.space_dashboard_rounded,
  ),
  projects(
    label: 'Projects',
    path: '/projects',
    icon: Icons.folder_outlined,
    selectedIcon: Icons.folder_rounded,
  ),
  issues(
    label: 'Issues',
    path: '/issues',
    icon: Icons.bug_report_outlined,
    selectedIcon: Icons.bug_report_rounded,
  ),
  cases(
    label: 'Cases',
    path: '/cases',
    icon: Icons.confirmation_number_outlined,
    selectedIcon: Icons.confirmation_number_rounded,
  ),
  reports(
    label: 'Reports',
    path: '/reports',
    icon: Icons.insert_chart_outlined_rounded,
    selectedIcon: Icons.insert_chart_rounded,
  ),
  settings(
    label: 'Settings',
    path: '/settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
  );

  const ConsoleDestination({
    required this.label,
    required this.path,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final String path;
  final IconData icon;
  final IconData selectedIcon;

  static ConsoleDestination fromPath(String path) {
    return ConsoleDestination.values.firstWhere(
      (ConsoleDestination destination) =>
          path == destination.path || path.startsWith('${destination.path}/'),
      orElse: () => ConsoleDestination.overview,
    );
  }
}

final class AppRouter {
  AppRouter({
    required AuthController authController,
    required ProjectController projectController,
    String initialLocation = '/overview',
  }) : router = GoRouter(
         initialLocation: initialLocation,
         refreshListenable: authController,
         redirect: (BuildContext context, GoRouterState state) {
           return _redirectForSession(authController.session, state);
         },
         routes: <RouteBase>[
           GoRoute(
             path: '/',
             redirect: (_, _) => ConsoleDestination.overview.path,
           ),
           GoRoute(
             path: bootstrapPath,
             builder: (_, _) => const AuthBootstrapPage(),
           ),
           GoRoute(
             path: signInPath,
             builder: (_, _) => SignInPage(authController: authController),
           ),
           GoRoute(
             path: unauthorizedPath,
             builder: (_, _) =>
                 UnauthorizedPage(authController: authController),
           ),
           GoRoute(
             path: sessionExpiredPath,
             builder: (_, _) =>
                 SessionExpiredPage(authController: authController),
           ),
           ShellRoute(
             builder:
                 (BuildContext context, GoRouterState state, Widget child) {
                   return ConsoleShell(
                     currentDestination: ConsoleDestination.fromPath(
                       state.uri.path,
                     ),
                     authSession: authController.session,
                     projectController: projectController,
                     onSignOut: () {
                       authController.signOut();
                     },
                     child: child,
                   );
                 },
             routes: <RouteBase>[
               GoRoute(
                 path: ConsoleDestination.overview.path,
                 builder: (_, _) => OverviewDashboardPage(
                   projectController: projectController,
                 ),
               ),
               GoRoute(
                 path: ConsoleDestination.projects.path,
                 builder: (_, _) => ProjectsPage(
                   controller: projectController,
                   authSession: authController.session,
                 ),
               ),
               GoRoute(
                 path: ConsoleDestination.issues.path,
                 builder: (_, GoRouterState state) => IssuesExplorerPage(
                   projectController: projectController,
                   uri: state.uri,
                 ),
               ),
               GoRoute(
                 path: ConsoleDestination.cases.path,
                 builder: (_, GoRouterState state) => CasesExplorerPage(
                   projectController: projectController,
                   uri: state.uri,
                 ),
                 routes: <RouteBase>[
                   GoRoute(
                     path: ':caseId',
                     builder: (_, GoRouterState state) => CaseDetailPage(
                       projectController: projectController,
                       caseId: state.pathParameters['caseId']!,
                     ),
                   ),
                 ],
               ),
               GoRoute(
                 path: ConsoleDestination.reports.path,
                 builder: (_, GoRouterState state) => ReportsDashboardPage(
                   projectController: projectController,
                   uri: state.uri,
                 ),
               ),
               GoRoute(
                 path: ConsoleDestination.settings.path,
                 builder: (_, _) =>
                     SettingsPage(projectController: projectController),
               ),
             ],
           ),
         ],
         errorBuilder: (_, GoRouterState state) {
           return RouterErrorPage(error: state.error);
         },
       );

  static const String bootstrapPath = '/boot';
  static const String signInPath = '/sign-in';
  static const String unauthorizedPath = '/unauthorized';
  static const String sessionExpiredPath = '/session-expired';

  final GoRouter router;

  static String? _redirectForSession(AuthSession session, GoRouterState state) {
    final String path = state.uri.path;
    final bool isBootstrapRoute = path == bootstrapPath;
    final bool isSignInRoute = path == signInPath;
    final bool isUnauthorizedRoute = path == unauthorizedPath;
    final bool isSessionExpiredRoute = path == sessionExpiredPath;
    final bool isAuthFlowRoute =
        isBootstrapRoute ||
        isSignInRoute ||
        isUnauthorizedRoute ||
        isSessionExpiredRoute;

    return switch (session.stage) {
      AuthStage.bootstrapping =>
        isBootstrapRoute ? null : _redirectToAuthRoute(bootstrapPath, state),
      AuthStage.signedOut =>
        isSignInRoute ? null : _redirectToAuthRoute(signInPath, state),
      AuthStage.sessionExpired =>
        isSessionExpiredRoute
            ? null
            : _redirectToAuthRoute(sessionExpiredPath, state),
      AuthStage.unauthorized =>
        isUnauthorizedRoute ? null : _redirectToAuthRoute(unauthorizedPath, state),
      AuthStage.authenticated =>
        isAuthFlowRoute
            ? _restoreAuthenticatedDestination(state)
            : (path == '/' ? ConsoleDestination.overview.path : null),
    };
  }

  static String _redirectToAuthRoute(String authPath, GoRouterState state) {
    final String from = _requestedLocation(state);
    return Uri(
      path: authPath,
      queryParameters: from == ConsoleDestination.overview.path
          ? null
          : <String, String>{'from': from},
    ).toString();
  }

  static String _restoreAuthenticatedDestination(GoRouterState state) {
    final String? from = state.uri.queryParameters['from'];
    if (from == null || from.isEmpty) {
      return ConsoleDestination.overview.path;
    }
    return from;
  }

  static String _requestedLocation(GoRouterState state) {
    final String path = state.uri.path;
    final bool isAuthRoute =
        path == bootstrapPath ||
        path == signInPath ||
        path == unauthorizedPath ||
        path == sessionExpiredPath;
    if (isAuthRoute) {
      return state.uri.queryParameters['from'] ?? ConsoleDestination.overview.path;
    }
    if (path == '/') {
      return ConsoleDestination.overview.path;
    }
    return state.uri.toString();
  }

  void dispose() {
    router.dispose();
  }
}
