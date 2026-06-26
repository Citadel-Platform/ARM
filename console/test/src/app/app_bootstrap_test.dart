import 'package:arm_console/src/app/app_bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('local dev session seeds the shared Citadel preview projects', () async {
    const AppBootstrapper bootstrapper = AppBootstrapper(
      enableLocalDevSession: true,
    );

    final authController = await bootstrapper.createAuthController();
    final projectController = await bootstrapper.createProjectController(
      authController,
    );

    await authController.start();
    projectController.start();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(authController.session.isSuperuser, isTrue);
    expect(
      projectController.visibleProjects.map((project) => project.id),
      orderedEquals(<String>[
        'core-platform',
        'customer-ops',
        'innovation-lab',
      ]),
    );

    projectController.dispose();
    authController.dispose();
  });
}
