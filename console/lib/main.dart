import 'package:arm_console/src/app/arm_console_app.dart';
import 'package:arm_console/src/app/app_bootstrap.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  const bool enableLocalDevSession = bool.fromEnvironment(
    'ARM_CONSOLE_ENABLE_LOCAL_DEV_SESSION',
  );
  final AppBootstrapper bootstrapper = AppBootstrapper(
    enableLocalDevSession: enableLocalDevSession,
  );
  final authController = await bootstrapper.createAuthController();
  runApp(ArmConsoleApp(authController: authController));
}
