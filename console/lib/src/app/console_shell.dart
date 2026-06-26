import 'dart:math' as math;

import 'package:arm_console/src/app/app_router.dart';
import 'package:arm_console/src/features/auth/domain/auth_models.dart';
import 'package:arm_console/src/features/projects/project_controller.dart';
import 'package:arm_console/src/features/projects/project_switcher.dart';
import 'package:arm_console/src/ui/console_primitives.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ConsoleShell extends StatelessWidget {
  const ConsoleShell({
    required this.currentDestination,
    required this.child,
    required this.authSession,
    required this.projectController,
    required this.onSignOut,
    super.key,
  });

  final ConsoleDestination currentDestination;
  final Widget child;
  final AuthSession authSession;
  final ProjectController projectController;
  final VoidCallback onSignOut;

  static const double _compactBreakpoint = 840;
  static const double _extendedRailBreakpoint = 1200;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool isCompact = constraints.maxWidth < _compactBreakpoint;
        final bool useExtendedRail =
            constraints.maxWidth >= _extendedRailBreakpoint;

        return Scaffold(
          backgroundColor: colorScheme.surfaceContainerLowest,
          drawer: isCompact
              ? Drawer(
                  child: SafeArea(
                    child: _ShellNavigation(
                      currentDestination: currentDestination,
                      onSelect: (ConsoleDestination destination) {
                        Navigator.of(context).pop();
                        context.go(destination.path);
                      },
                      useRail: false,
                      authSession: authSession,
                      projectController: projectController,
                    ),
                  ),
                )
              : null,
          appBar: AppBar(
            toolbarHeight: 76,
            automaticallyImplyLeading: false,
            leading: isCompact
                ? Builder(
                    builder: (BuildContext context) {
                      return IconButton(
                        tooltip: 'Open navigation menu',
                        icon: const Icon(Icons.menu_rounded),
                        onPressed: Scaffold.of(context).openDrawer,
                      );
                    },
                  )
                : null,
            titleSpacing: isCompact ? 0 : 24,
            title: _ShellHeader(
              destination: currentDestination,
              authSession: authSession,
              projectController: projectController,
            ),
            actions: <Widget>[
              _ShellSearchField(compact: isCompact),
              const SizedBox(width: 12),
              if (!isCompact) ProjectSwitcher(controller: projectController),
              IconButton(
                tooltip: 'Notifications placeholder',
                onPressed: () {},
                icon: const Icon(Icons.notifications_none_rounded),
              ),
              _SessionMenu(email: authSession.email, onSignOut: onSignOut),
              const SizedBox(width: 16),
            ],
          ),
          body: SafeArea(
            top: false,
            child: isCompact
                ? child
                : Row(
                    children: <Widget>[
                      Container(
                        width: useExtendedRail ? 288 : 104,
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          border: Border(
                            right: BorderSide(
                              color: colorScheme.outlineVariant,
                            ),
                          ),
                        ),
                        child: _ShellNavigation(
                          currentDestination: currentDestination,
                          onSelect: (ConsoleDestination destination) {
                            context.go(destination.path);
                          },
                          useRail: true,
                          extended: useExtendedRail,
                          authSession: authSession,
                          projectController: projectController,
                        ),
                      ),
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerLowest,
                          ),
                          child: child,
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _ShellHeader extends StatelessWidget {
  const _ShellHeader({
    required this.destination,
    required this.authSession,
    required this.projectController,
  });

  final ConsoleDestination destination;
  final AuthSession authSession;
  final ProjectController projectController;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;

    return ListenableBuilder(
      listenable: projectController,
      builder: (BuildContext context, Widget? child) {
        final String scopeLabel = authSession.role == AuthRole.superuser
            ? projectController.selectionLabel
            : projectController.selectionLabel == 'Loading projects'
            ? destination.label
            : projectController.selectionLabel;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'ARM Console',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '${destination.label} · $scopeLabel',
              style: textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ShellSearchField extends StatelessWidget {
  const _ShellSearchField({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton(
        tooltip: 'Global search placeholder',
        onPressed: () {},
        icon: const Icon(Icons.search_rounded),
      );
    }

    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Tooltip(
      message:
          'Global search will be connected with issue and case deep links.',
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        height: 46,
        margin: const EdgeInsets.symmetric(vertical: 14),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.search_rounded,
              color: colorScheme.onSurfaceVariant,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Search cases, issues, and traces',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Soon',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionMenu extends StatelessWidget {
  const _SessionMenu({required this.email, required this.onSignOut});

  final String? email;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_SessionAction>(
      tooltip: email ?? 'Session actions',
      onSelected: (_SessionAction action) {
        if (action == _SessionAction.signOut) {
          onSignOut();
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<_SessionAction>>[
        PopupMenuItem<_SessionAction>(
          enabled: false,
          child: Text(email ?? 'Signed in'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<_SessionAction>(
          value: _SessionAction.signOut,
          child: Text('Sign out'),
        ),
      ],
      child: const CircleAvatar(
        radius: 18,
        child: Icon(Icons.person_outline_rounded, size: 18),
      ),
    );
  }
}

enum _SessionAction { signOut }

class _ShellNavigation extends StatelessWidget {
  const _ShellNavigation({
    required this.currentDestination,
    required this.onSelect,
    required this.useRail,
    required this.authSession,
    required this.projectController,
    this.extended = false,
  });

  final ConsoleDestination currentDestination;
  final ValueChanged<ConsoleDestination> onSelect;
  final bool useRail;
  final bool extended;
  final AuthSession authSession;
  final ProjectController projectController;

  @override
  Widget build(BuildContext context) {
    final List<ConsoleDestination> destinations = ConsoleDestination.values;

    if (useRail) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.only(left: extended ? 12 : 0, bottom: 12),
            child: const _NavigationLabel(),
          ),
          Expanded(
            child: NavigationRail(
              extended: extended,
              minExtendedWidth: 256,
              selectedIndex: destinations.indexOf(currentDestination),
              useIndicator: true,
              onDestinationSelected: (int index) {
                onSelect(destinations[index]);
              },
              destinations: destinations
                  .map(
                    (ConsoleDestination destination) =>
                        NavigationRailDestination(
                          icon: Icon(destination.icon),
                          selectedIcon: Icon(destination.selectedIcon),
                          label: Text(destination.label),
                        ),
                  )
                  .toList(),
            ),
          ),
          ConsoleSurface(
            padding: const EdgeInsets.all(16),
            child: Text(
              authSession.role == AuthRole.superuser
                  ? 'Superuser claims unlock cross-project access and registry control across the console.'
                  : 'Project-scoped developer and viewer sessions stay limited to their assigned projects.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _NavigationLabel(),
          const SizedBox(height: 16),
          Expanded(
            child: NavigationDrawer(
              selectedIndex: destinations.indexOf(currentDestination),
              onDestinationSelected: (int index) {
                onSelect(destinations[index]);
              },
              children: <Widget>[
                for (final ConsoleDestination destination in destinations)
                  NavigationDrawerDestination(
                    icon: Icon(destination.icon),
                    selectedIcon: Icon(destination.selectedIcon),
                    label: Text(destination.label),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ProjectSwitcher(controller: projectController, compact: true),
        ],
      ),
    );
  }
}

class _NavigationLabel extends StatelessWidget {
  const _NavigationLabel();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Release 1',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Operations',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class RouterErrorPage extends StatelessWidget {
  const RouterErrorPage({this.error, super.key});

  final Exception? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ConsolePageBody(
        child: ConsoleStateView.error(
          title: 'Route unavailable',
          message:
              error?.toString() ??
              'The requested page could not be opened from the current route.',
        ),
      ),
    );
  }
}

double clampPanelWidth(double width) {
  return math.min(width, 1440);
}
