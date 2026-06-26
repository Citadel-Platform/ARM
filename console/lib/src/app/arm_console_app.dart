import 'package:arm_console/src/app/app_bootstrap.dart';
import 'package:arm_console/src/app/app_router.dart';
import 'package:arm_console/src/features/auth/auth_controller.dart';
import 'package:arm_console/src/features/projects/project_controller.dart';
import 'package:arm_console/src/ui/console_theme.dart';
import 'package:flutter/material.dart';

class ArmConsoleApp extends StatefulWidget {
  const ArmConsoleApp({
    super.key,
    this.bootstrapper = const AppBootstrapper(),
    this.authController,
    this.projectController,
    this.initialLocation = '/overview',
  });

  final AppBootstrapper bootstrapper;
  final AuthController? authController;
  final ProjectController? projectController;
  final String initialLocation;

  @override
  State<ArmConsoleApp> createState() => _ArmConsoleAppState();
}

class _ArmConsoleAppState extends State<ArmConsoleApp> {
  late final Future<_AppControllers> _controllersFuture = _createControllers();

  AppRouter? _router;
  AuthController? _authController;
  ProjectController? _projectController;

  Future<_AppControllers> _createControllers() async {
    final AuthController authController =
        widget.authController ?? await widget.bootstrapper.createAuthController();
    final ProjectController projectController =
        widget.projectController ??
        await widget.bootstrapper.createProjectController(authController);
    return _AppControllers(
      authController: authController,
      projectController: projectController,
    );
  }

  _AppControllers _attachControllers(_AppControllers controllers) {
    if (!identical(_authController, controllers.authController) ||
        !identical(_projectController, controllers.projectController)) {
      _router?.dispose();
      _authController = controllers.authController;
      _projectController = controllers.projectController;
      _router = AppRouter(
        authController: controllers.authController,
        projectController: controllers.projectController,
        initialLocation: widget.initialLocation,
      );
      controllers.authController.start();
      controllers.projectController.start();
    }

    return controllers;
  }

  @override
  void dispose() {
    _router?.dispose();
    _projectController?.dispose();
    _authController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AppControllers>(
      future: _controllersFuture,
      builder: (
        BuildContext context,
        AsyncSnapshot<_AppControllers> snapshot,
      ) {
        if (!snapshot.hasData) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildConsoleTheme(),
            home: const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        _attachControllers(snapshot.data!);

        return MaterialApp.router(
          title: 'ARM Console',
          debugShowCheckedModeBanner: false,
          theme: buildConsoleTheme(),
          routerConfig: _router!.router,
        );
      },
    );
  }
}

class _AppControllers {
  const _AppControllers({
    required this.authController,
    required this.projectController,
  });

  final AuthController authController;
  final ProjectController projectController;
}
