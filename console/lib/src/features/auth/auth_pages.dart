import 'package:arm_console/src/features/auth/auth_controller.dart';
import 'package:arm_console/src/features/auth/domain/auth_models.dart';
import 'package:arm_console/src/ui/console_primitives.dart';
import 'package:flutter/material.dart';

class AuthBootstrapPage extends StatelessWidget {
  const AuthBootstrapPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: ConsolePageBody(
        child: SizedBox(
          height: 480,
          child: ConsoleStateView.loading(
            title: 'Bootstrapping console session',
            message:
                'Validating Firebase auth state and loading project access scope.',
          ),
        ),
      ),
    );
  }
}

class SignInPage extends StatelessWidget {
  const SignInPage({required this.authController, super.key});

  final AuthController authController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: authController,
      builder: (BuildContext context, _) {
        final AuthSession session = authController.session;
        final bool isBusy = session.isActionInProgress;
        final bool canInteractiveSignIn = authController.canInteractiveSignIn;
        final String defaultMessage = canInteractiveSignIn
            ? 'Authentication uses Firebase Auth. The superuser account is granted through custom claims, while project-scoped developer and viewer roles are loaded from the console access repository.'
            : (authController.signInUnavailableReason ??
                  'Sign-in is unavailable because the console Firebase configuration is incomplete.');

        return Scaffold(
          body: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  Theme.of(context).colorScheme.primaryContainer,
                  Theme.of(context).colorScheme.surfaceContainerLowest,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: ConsoleFormSection(
                  title: 'ARM Console sign in',
                  description:
                      'Sign in with Google to restore your scoped project access.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Signed-out',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        session.message ?? defaultMessage,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: isBusy || !canInteractiveSignIn
                            ? null
                            : () {
                                authController.signInWithGoogle();
                              },
                        icon: isBusy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.login_rounded),
                        label: Text(
                          isBusy ? 'Signing in...' : 'Continue with Google',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class UnauthorizedPage extends StatelessWidget {
  const UnauthorizedPage({required this.authController, super.key});

  final AuthController authController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: authController,
      builder: (BuildContext context, _) {
        final AuthSession session = authController.session;
        return Scaffold(
          body: ConsolePageBody(
            child: SizedBox(
              height: 520,
              child: ConsoleStateView.noAccess(
                title: 'Unauthorized account',
                message:
                    session.message ??
                    'Your email is not mapped to any developer or viewer project scope in '
                        'the console access repository.',
                actionLabel: 'Sign out',
                onAction: () {
                  authController.signOut();
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class SessionExpiredPage extends StatelessWidget {
  const SessionExpiredPage({required this.authController, super.key});

  final AuthController authController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: authController,
      builder: (BuildContext context, _) {
        final AuthSession session = authController.session;
        return Scaffold(
          body: ConsolePageBody(
            child: SizedBox(
              height: 520,
              child: ConsoleStateView.error(
                title: 'Session expired',
                message:
                    session.message ??
                    'Sign in again to refresh your console session and scope.',
                actionLabel: 'Return to sign in',
                onAction: () {
                  authController.signOut();
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
